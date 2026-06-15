use crate::ast::{Direction, FlowchartDirective, FlowchartHeader, Span, Spanned};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Parser;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlowchartHeaderTokenKind {
    Directive(FlowchartDirective),
    Direction(Direction),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FlowchartHeaderToken {
    pub kind: FlowchartHeaderTokenKind,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseErrorKind {
    ExpectedFlowchartDirective,
    ExpectedFlowchartDirection,
    UnknownFlowchartDirective,
    UnknownFlowchartDirection,
    TrailingInput,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError {
    pub kind: ParseErrorKind,
    pub span: Span,
}

impl Parser {
    pub fn lex_flowchart_header(source: &str) -> Result<Vec<FlowchartHeaderToken>, ParseError> {
        FlowchartHeaderLexer::new(source).lex()
    }

    pub fn parse_flowchart_header(source: &str) -> Result<FlowchartHeader, ParseError> {
        let tokens = Self::lex_flowchart_header(source)?;
        let [directive, direction] = tokens.as_slice() else {
            unreachable!("flowchart header lexer returns exactly two tokens on success");
        };
        let FlowchartHeaderTokenKind::Directive(directive_value) = directive.kind else {
            unreachable!("flowchart header lexer returns directive first");
        };
        let FlowchartHeaderTokenKind::Direction(direction_value) = direction.kind else {
            unreachable!("flowchart header lexer returns direction second");
        };

        Ok(FlowchartHeader {
            directive: Spanned::new(directive_value, directive.span),
            direction: Spanned::new(direction_value, direction.span),
            span: Span::new(directive.span.start, direction.span.end),
        })
    }
}

struct FlowchartHeaderLexer<'source> {
    source: &'source str,
    cursor: usize,
}

impl<'source> FlowchartHeaderLexer<'source> {
    fn new(source: &'source str) -> Self {
        let end = source.find(['\n', '\r']).unwrap_or(source.len());
        Self {
            source: &source[..end],
            cursor: 0,
        }
    }

    fn lex(&mut self) -> Result<Vec<FlowchartHeaderToken>, ParseError> {
        self.skip_ws();
        let directive = self.lex_directive()?;
        self.skip_ws();
        let direction = self.lex_direction()?;
        self.skip_ws();
        if self.peek_byte() == Some(b';') {
            self.cursor += 1;
            self.skip_ws();
        }
        if self.cursor != self.source.len() {
            return Err(ParseError {
                kind: ParseErrorKind::TrailingInput,
                span: Span::new(self.cursor, self.source.len()),
            });
        }
        Ok(vec![directive, direction])
    }

    fn lex_directive(&mut self) -> Result<FlowchartHeaderToken, ParseError> {
        let Some((value, span)) = self.take_word() else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedFlowchartDirective,
                span: Span::new(self.cursor, self.cursor),
            });
        };
        let directive = match value {
            "flowchart" => FlowchartDirective::Flowchart,
            "graph" => FlowchartDirective::Graph,
            _ => {
                return Err(ParseError {
                    kind: ParseErrorKind::UnknownFlowchartDirective,
                    span,
                });
            }
        };
        Ok(FlowchartHeaderToken {
            kind: FlowchartHeaderTokenKind::Directive(directive),
            span,
        })
    }

    fn lex_direction(&mut self) -> Result<FlowchartHeaderToken, ParseError> {
        let Some((value, span)) = self.take_word() else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedFlowchartDirection,
                span: Span::new(self.cursor, self.cursor),
            });
        };
        let Some(direction) = Direction::from_mermaid(value) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownFlowchartDirection,
                span,
            });
        };
        Ok(FlowchartHeaderToken {
            kind: FlowchartHeaderTokenKind::Direction(direction),
            span,
        })
    }

    fn take_word(&mut self) -> Option<(&'source str, Span)> {
        let start = self.cursor;
        while matches!(self.peek_byte(), Some(value) if value.is_ascii_alphanumeric()) {
            self.cursor += 1;
        }
        (self.cursor > start).then(|| {
            (
                &self.source[start..self.cursor],
                Span::new(start, self.cursor),
            )
        })
    }

    fn skip_ws(&mut self) {
        while matches!(self.peek_byte(), Some(b' ' | b'\t')) {
            self.cursor += 1;
        }
    }

    fn peek_byte(&self) -> Option<u8> {
        self.source.as_bytes().get(self.cursor).copied()
    }
}

#[cfg(test)]
mod tests {
    use super::{
        FlowchartHeaderToken, FlowchartHeaderTokenKind, ParseError, ParseErrorKind, Parser,
    };
    use crate::ast::{Direction, FlowchartDirective, Span};

    #[test]
    fn lexes_flowchart_header_tokens_with_spans() {
        assert_eq!(
            Parser::lex_flowchart_header("  graph LR").unwrap(),
            vec![
                FlowchartHeaderToken {
                    kind: FlowchartHeaderTokenKind::Directive(FlowchartDirective::Graph),
                    span: Span::new(2, 7),
                },
                FlowchartHeaderToken {
                    kind: FlowchartHeaderTokenKind::Direction(Direction::LeftRight),
                    span: Span::new(8, 10),
                },
            ],
        );
    }

    #[test]
    fn parses_graph_and_flowchart_directions() {
        let cases = [
            ("graph TD", FlowchartDirective::Graph, Direction::TopDown),
            ("graph TB", FlowchartDirective::Graph, Direction::TopDown),
            ("graph BT", FlowchartDirective::Graph, Direction::BottomTop),
            ("graph LR", FlowchartDirective::Graph, Direction::LeftRight),
            ("graph RL", FlowchartDirective::Graph, Direction::RightLeft),
            (
                "flowchart TD",
                FlowchartDirective::Flowchart,
                Direction::TopDown,
            ),
        ];

        for (source, directive, direction) in cases {
            let header = Parser::parse_flowchart_header(source).unwrap();

            assert_eq!(header.directive.value, directive);
            assert_eq!(header.direction.value, direction);
        }
    }

    #[test]
    fn parses_header_from_first_source_line() {
        let header = Parser::parse_flowchart_header("flowchart BT\nA --> B").unwrap();

        assert_eq!(header.directive.value, FlowchartDirective::Flowchart);
        assert_eq!(header.direction.value, Direction::BottomTop);
        assert_eq!(header.span, Span::new(0, 12));
    }

    #[test]
    fn allows_trailing_semicolon() {
        let header = Parser::parse_flowchart_header("\tgraph LR;  ").unwrap();

        assert_eq!(header.directive.span, Span::new(1, 6));
        assert_eq!(header.direction.value, Direction::LeftRight);
    }

    #[test]
    fn rejects_missing_direction() {
        assert_eq!(
            Parser::parse_flowchart_header("graph").unwrap_err(),
            ParseError {
                kind: ParseErrorKind::ExpectedFlowchartDirection,
                span: Span::new(5, 5),
            },
        );
    }

    #[test]
    fn rejects_unknown_direction() {
        assert_eq!(
            Parser::parse_flowchart_header("graph DOWN").unwrap_err(),
            ParseError {
                kind: ParseErrorKind::UnknownFlowchartDirection,
                span: Span::new(6, 10),
            },
        );
    }

    #[test]
    fn rejects_trailing_header_input() {
        assert_eq!(
            Parser::parse_flowchart_header("graph LR extra").unwrap_err(),
            ParseError {
                kind: ParseErrorKind::TrailingInput,
                span: Span::new(9, 14),
            },
        );
    }
}
