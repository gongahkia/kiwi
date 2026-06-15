use crate::ast::{
    Direction, FlowNode, FlowShape, FlowchartDirective, FlowchartHeader, Label, LabelKind, Span,
    Spanned,
};

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
    ExpectedFlowNodeId,
    MissingFlowNodeShape,
    UnknownFlowNodeShape,
    UnterminatedFlowNodeShape,
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

    pub fn parse_flow_node(source: &str) -> Result<FlowNode, ParseError> {
        FlowNodeParser::new(source).parse()
    }
}

struct FlowNodeParser<'source> {
    source: &'source str,
    cursor: usize,
}

impl<'source> FlowNodeParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
            cursor: 0,
        }
    }

    fn parse(&mut self) -> Result<FlowNode, ParseError> {
        self.skip_ws();
        let id = self.take_node_id()?;
        self.skip_ws();

        let (shape, label, node_end) = match self.peek_byte() {
            Some(b'@') => self.parse_named_shape()?,
            Some(b'[' | b'(' | b'{' | b'>') => self.parse_classic_shape()?,
            _ => (
                Spanned::new(FlowShape::Rectangle, id.span),
                None,
                id.span.end,
            ),
        };

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

        Ok(FlowNode {
            span: Span::new(id.span.start, node_end),
            id,
            label,
            shape,
        })
    }

    fn take_node_id(&mut self) -> Result<Spanned<String>, ParseError> {
        let start = self.cursor;
        let Some(first) = self.peek_byte() else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedFlowNodeId,
                span: Span::new(start, start),
            });
        };
        if !first.is_ascii_alphanumeric() && first != b'_' {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedFlowNodeId,
                span: Span::new(start, start),
            });
        }
        self.cursor += 1;
        while matches!(self.peek_byte(), Some(value) if value.is_ascii_alphanumeric() || value == b'_' || value == b'-')
        {
            self.cursor += 1;
        }
        Ok(Spanned::new(
            self.source[start..self.cursor].to_owned(),
            Span::new(start, self.cursor),
        ))
    }

    fn parse_classic_shape(
        &mut self,
    ) -> Result<(Spanned<FlowShape>, Option<Label>, usize), ParseError> {
        let start = self.cursor;
        if self.consume("(((") {
            return self.parse_fixed_shape(start, ")))", FlowShape::DoubleCircle);
        }
        if self.consume("((") {
            return self.parse_fixed_shape(start, "))", FlowShape::Circle);
        }
        if self.consume("([") {
            return self.parse_fixed_shape(start, "])", FlowShape::Stadium);
        }
        if self.consume("[(") {
            return self.parse_fixed_shape(start, ")]", FlowShape::Cylinder);
        }
        if self.consume("(") {
            return self.parse_fixed_shape(start, ")", FlowShape::Round);
        }
        if self.consume("[[") {
            return self.parse_fixed_shape(start, "]]", FlowShape::Subroutine);
        }
        if self.consume("[/") {
            return self.parse_one_of_shapes(
                start,
                &[
                    ("/]", FlowShape::Parallelogram),
                    (r"\]", FlowShape::Trapezoid),
                ],
            );
        }
        if self.consume(r"[\") {
            return self.parse_one_of_shapes(
                start,
                &[
                    (r"\]", FlowShape::ParallelogramAlt),
                    ("/]", FlowShape::TrapezoidAlt),
                ],
            );
        }
        if self.consume("[") {
            return self.parse_fixed_shape(start, "]", FlowShape::Rectangle);
        }
        if self.consume("{{") {
            return self.parse_fixed_shape(start, "}}", FlowShape::Hexagon);
        }
        if self.consume("{") {
            return self.parse_fixed_shape(start, "}", FlowShape::Rhombus);
        }
        if self.consume(">") {
            return self.parse_fixed_shape(start, "]", FlowShape::Asymmetric);
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownFlowNodeShape,
            span: Span::new(start, start + 1),
        })
    }

    fn parse_fixed_shape(
        &mut self,
        start: usize,
        close: &str,
        shape: FlowShape,
    ) -> Result<(Spanned<FlowShape>, Option<Label>, usize), ParseError> {
        let body_start = self.cursor;
        let Some(close_offset) = self.source[body_start..].find(close) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnterminatedFlowNodeShape,
                span: Span::new(start, self.source.len()),
            });
        };
        let body_end = body_start + close_offset;
        self.cursor = body_end + close.len();
        Ok((
            Spanned::new(shape, Span::new(start, self.cursor)),
            Some(self.label_from_body(body_start, body_end)),
            self.cursor,
        ))
    }

    fn parse_one_of_shapes(
        &mut self,
        start: usize,
        choices: &[(&str, FlowShape)],
    ) -> Result<(Spanned<FlowShape>, Option<Label>, usize), ParseError> {
        let body_start = self.cursor;
        let Some((close_offset, close, shape)) = choices
            .iter()
            .filter_map(|(close, shape)| {
                self.source[body_start..]
                    .find(close)
                    .map(|offset| (offset, *close, shape.clone()))
            })
            .min_by_key(|(offset, _, _)| *offset)
        else {
            return Err(ParseError {
                kind: ParseErrorKind::UnterminatedFlowNodeShape,
                span: Span::new(start, self.source.len()),
            });
        };
        let body_end = body_start + close_offset;
        self.cursor = body_end + close.len();
        Ok((
            Spanned::new(shape, Span::new(start, self.cursor)),
            Some(self.label_from_body(body_start, body_end)),
            self.cursor,
        ))
    }

    fn parse_named_shape(
        &mut self,
    ) -> Result<(Spanned<FlowShape>, Option<Label>, usize), ParseError> {
        let start = self.cursor;
        self.cursor += 1;
        if self.peek_byte() != Some(b'{') {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownFlowNodeShape,
                span: Span::new(start, self.cursor),
            });
        }
        self.cursor += 1;
        let body_start = self.cursor;
        let Some(close_offset) = self.source[body_start..].find('}') else {
            return Err(ParseError {
                kind: ParseErrorKind::UnterminatedFlowNodeShape,
                span: Span::new(start, self.source.len()),
            });
        };
        let body_end = body_start + close_offset;
        let shape = self.parse_named_shape_value(body_start, body_end)?;
        self.cursor = body_end + 1;
        Ok((shape, None, self.cursor))
    }

    fn parse_named_shape_value(
        &self,
        body_start: usize,
        body_end: usize,
    ) -> Result<Spanned<FlowShape>, ParseError> {
        let body = &self.source[body_start..body_end];
        let mut field_start = 0;
        for field in body.split(',') {
            if let Some(shape) = self.parse_named_shape_field(body_start + field_start, field)? {
                return Ok(shape);
            }
            field_start += field.len() + 1;
        }
        Err(ParseError {
            kind: ParseErrorKind::MissingFlowNodeShape,
            span: Span::new(body_start, body_end),
        })
    }

    fn parse_named_shape_field(
        &self,
        field_start: usize,
        field: &str,
    ) -> Result<Option<Spanned<FlowShape>>, ParseError> {
        let Some(colon) = field.find(':') else {
            return Ok(None);
        };
        let key = &field[..colon];
        let Some((key_start, key_end)) = trim_ascii_range(key) else {
            return Ok(None);
        };
        if &key[key_start..key_end] != "shape" {
            return Ok(None);
        }

        let value = &field[colon + 1..];
        let Some((mut value_start, mut value_end)) = trim_ascii_range(value) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownFlowNodeShape,
                span: Span::new(field_start + colon + 1, field_start + field.len()),
            });
        };
        let mut value_text = &value[value_start..value_end];
        if value_text.len() >= 2
            && value_text.as_bytes().first() == Some(&b'"')
            && value_text.as_bytes().last() == Some(&b'"')
        {
            value_start += 1;
            value_end -= 1;
            value_text = &value[value_start..value_end];
        }
        if value_text.is_empty()
            || !value_text
                .as_bytes()
                .iter()
                .all(|value| value.is_ascii_alphanumeric() || *value == b'-' || *value == b'_')
        {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownFlowNodeShape,
                span: Span::new(
                    field_start + colon + 1 + value_start,
                    field_start + colon + 1 + value_end,
                ),
            });
        }
        Ok(Some(Spanned::new(
            FlowShape::Named(value_text.to_owned()),
            Span::new(
                field_start + colon + 1 + value_start,
                field_start + colon + 1 + value_end,
            ),
        )))
    }

    fn label_from_body(&self, start: usize, end: usize) -> Label {
        let raw = &self.source[start..end];
        if raw.len() >= 2
            && raw.as_bytes().first() == Some(&b'"')
            && raw.as_bytes().last() == Some(&b'"')
        {
            let quoted_start = start + 1;
            let quoted_end = end - 1;
            let quoted = &self.source[quoted_start..quoted_end];
            if quoted.len() >= 2
                && quoted.as_bytes().first() == Some(&b'`')
                && quoted.as_bytes().last() == Some(&b'`')
            {
                return Label {
                    text: self.source[quoted_start + 1..quoted_end - 1].to_owned(),
                    kind: LabelKind::Markdown,
                    span: Span::new(quoted_start + 1, quoted_end - 1),
                };
            }
            return Label {
                text: quoted.to_owned(),
                kind: LabelKind::String,
                span: Span::new(quoted_start, quoted_end),
            };
        }
        Label {
            text: raw.to_owned(),
            kind: LabelKind::Plain,
            span: Span::new(start, end),
        }
    }

    fn consume(&mut self, value: &str) -> bool {
        if !self.source[self.cursor..].starts_with(value) {
            return false;
        }
        self.cursor += value.len();
        true
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

struct FlowchartHeaderLexer<'source> {
    source: &'source str,
    cursor: usize,
}

impl<'source> FlowchartHeaderLexer<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
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

fn first_line(source: &str) -> &str {
    let end = source.find(['\n', '\r']).unwrap_or(source.len());
    &source[..end]
}

fn trim_ascii_range(value: &str) -> Option<(usize, usize)> {
    let bytes = value.as_bytes();
    let mut start = 0;
    let mut end = bytes.len();
    while start < end && bytes[start].is_ascii_whitespace() {
        start += 1;
    }
    while end > start && bytes[end - 1].is_ascii_whitespace() {
        end -= 1;
    }
    (start < end).then_some((start, end))
}

#[cfg(test)]
mod tests {
    use super::{
        FlowchartHeaderToken, FlowchartHeaderTokenKind, ParseError, ParseErrorKind, Parser,
    };
    use crate::ast::{Direction, FlowShape, FlowchartDirective, LabelKind, Span};

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

    #[test]
    fn parses_bare_flow_node_id() {
        let node = Parser::parse_flow_node("Node_1-2").unwrap();

        assert_eq!(node.id.value, "Node_1-2");
        assert_eq!(node.id.span, Span::new(0, 8));
        assert_eq!(node.shape.value, FlowShape::Rectangle);
        assert_eq!(node.label, None);
    }

    #[test]
    fn parses_classic_flow_node_shapes() {
        let cases = [
            ("A[rect]", FlowShape::Rectangle, "rect"),
            ("A(round)", FlowShape::Round, "round"),
            ("A([stadium])", FlowShape::Stadium, "stadium"),
            ("A[[subroutine]]", FlowShape::Subroutine, "subroutine"),
            ("A[(database)]", FlowShape::Cylinder, "database"),
            ("A((circle))", FlowShape::Circle, "circle"),
            ("A>asymmetric]", FlowShape::Asymmetric, "asymmetric"),
            ("A{diamond}", FlowShape::Rhombus, "diamond"),
            ("A{{hexagon}}", FlowShape::Hexagon, "hexagon"),
            (
                "A[/parallelogram/]",
                FlowShape::Parallelogram,
                "parallelogram",
            ),
            (
                r"A[\parallelogram\]",
                FlowShape::ParallelogramAlt,
                "parallelogram",
            ),
            (r"A[/trapezoid\]", FlowShape::Trapezoid, "trapezoid"),
            (r"A[\trapezoid/]", FlowShape::TrapezoidAlt, "trapezoid"),
            ("A(((double)))", FlowShape::DoubleCircle, "double"),
        ];

        for (source, shape, label) in cases {
            let node = Parser::parse_flow_node(source).unwrap();

            assert_eq!(node.id.value, "A");
            assert_eq!(node.shape.value, shape);
            assert_eq!(node.label.unwrap().text, label);
        }
    }

    #[test]
    fn parses_quoted_and_markdown_labels() {
        let quoted = Parser::parse_flow_node(r#"A["line1\nline2"]"#).unwrap();
        let markdown = Parser::parse_flow_node(r#"A["`strong`"]"#).unwrap();

        let quoted_label = quoted.label.unwrap();
        assert_eq!(quoted_label.kind, LabelKind::String);
        assert_eq!(quoted_label.text, r"line1\nline2");
        assert_eq!(quoted_label.span, Span::new(3, 15));

        let markdown_label = markdown.label.unwrap();
        assert_eq!(markdown_label.kind, LabelKind::Markdown);
        assert_eq!(markdown_label.text, "strong");
    }

    #[test]
    fn parses_named_flow_node_shape() {
        let node = Parser::parse_flow_node("A@{ shape: notch-rect }").unwrap();

        assert_eq!(node.id.value, "A");
        assert_eq!(node.shape.value, FlowShape::Named("notch-rect".to_owned()));
        assert_eq!(node.shape.span, Span::new(11, 21));
        assert_eq!(node.span, Span::new(0, 23));
    }

    #[test]
    fn parses_quoted_named_flow_node_shape() {
        let node = Parser::parse_flow_node(r#"A@{shape:"rect"}"#).unwrap();

        assert_eq!(node.shape.value, FlowShape::Named("rect".to_owned()));
        assert_eq!(node.shape.span, Span::new(10, 14));
    }

    #[test]
    fn rejects_missing_flow_node_id() {
        assert_eq!(
            Parser::parse_flow_node("-->").unwrap_err().kind,
            ParseErrorKind::ExpectedFlowNodeId,
        );
    }

    #[test]
    fn rejects_missing_named_flow_node_shape() {
        assert_eq!(
            Parser::parse_flow_node(r#"A@{ label: "x" }"#)
                .unwrap_err()
                .kind,
            ParseErrorKind::MissingFlowNodeShape,
        );
    }

    #[test]
    fn rejects_unterminated_flow_node_shape() {
        assert_eq!(
            Parser::parse_flow_node("A[/open").unwrap_err().kind,
            ParseErrorKind::UnterminatedFlowNodeShape,
        );
    }

    #[test]
    fn rejects_trailing_flow_node_input() {
        assert_eq!(
            Parser::parse_flow_node("A B").unwrap_err(),
            ParseError {
                kind: ParseErrorKind::TrailingInput,
                span: Span::new(2, 3),
            },
        );
    }
}
