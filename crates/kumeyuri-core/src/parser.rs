use crate::ast::{
    ArrowHead, Direction, FlowClassApply, FlowClassDef, FlowEdge, FlowEdgeLink, FlowEdgeStroke,
    FlowNode, FlowShape, FlowStatement, FlowStyleDeclaration, FlowSubgraph, FlowchartDirective,
    FlowchartHeader, Label, LabelKind, MermaidComment, MermaidDirective, Span, Spanned,
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
    ExpectedFlowEdge,
    ExpectedSubgraphHeader,
    ExpectedSubgraphId,
    UnterminatedSubgraph,
    UnknownFlowStatement,
    ExpectedClassDef,
    ExpectedClassName,
    ExpectedStyleDeclaration,
    ExpectedClassStatement,
    ExpectedClassNode,
    ExpectedComment,
    ExpectedDirective,
    UnterminatedDirective,
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

    pub fn parse_flow_edge(source: &str) -> Result<FlowEdge, ParseError> {
        FlowEdgeParser::new(source).parse()
    }

    pub fn parse_flow_subgraph(source: &str) -> Result<FlowSubgraph, ParseError> {
        FlowSubgraphParser::new(source).parse()
    }

    pub fn parse_flow_class_def(source: &str) -> Result<FlowClassDef, ParseError> {
        FlowClassDefParser::new(source).parse()
    }

    pub fn parse_flow_class_apply(source: &str) -> Result<FlowClassApply, ParseError> {
        FlowClassApplyParser::new(source).parse()
    }

    pub fn parse_mermaid_comment(source: &str) -> Result<MermaidComment, ParseError> {
        MermaidCommentParser::new(source).parse()
    }

    pub fn parse_mermaid_directive(source: &str) -> Result<MermaidDirective, ParseError> {
        MermaidDirectiveParser::new(source).parse()
    }
}

struct FlowEdgeParser<'source> {
    source: &'source str,
    cursor: usize,
}

struct FlowClassDefParser<'source> {
    source: &'source str,
}

impl<'source> FlowClassDefParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<FlowClassDef, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedClassDef,
                span: Span::new(0, 0),
            });
        };
        let keyword = "classDef";
        if !has_keyword(self.source, start, keyword) {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedClassDef,
                span: Span::new(start, end),
            });
        }

        let rest_start = start + keyword.len();
        let Some((rest_trim_start, rest_trim_end)) =
            trim_ascii_range(&self.source[rest_start..end])
        else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedClassName,
                span: Span::new(rest_start, end),
            });
        };
        let rest_start = rest_start + rest_trim_start;
        let rest_end = start + keyword.len() + rest_trim_end;
        let rest = &self.source[rest_start..rest_end];
        let Some(colon) = rest.find(':') else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedStyleDeclaration,
                span: Span::new(rest_start, rest_end),
            });
        };
        let Some(style_start) = rest[..colon].rfind(|value: char| value.is_ascii_whitespace())
        else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedClassName,
                span: Span::new(rest_start, rest_start + colon),
            });
        };

        let class_ids = parse_csv_identifiers(
            self.source,
            rest_start,
            rest_start + style_start,
            ParseErrorKind::ExpectedClassName,
        )?;
        let styles = parse_style_declarations(self.source, rest_start + style_start, rest_end)?;
        Ok(FlowClassDef {
            class_ids,
            styles,
            span: Span::new(start, end),
        })
    }
}

struct FlowClassApplyParser<'source> {
    source: &'source str,
}

struct MermaidCommentParser<'source> {
    source: &'source str,
}

impl<'source> MermaidCommentParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<MermaidComment, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedComment,
                span: Span::new(0, 0),
            });
        };
        if !self.source[start..end].starts_with("%%") || self.source[start..end].starts_with("%%{")
        {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedComment,
                span: Span::new(start, end),
            });
        }
        let text_start = start + 2;
        let text = trim_ascii_range(&self.source[text_start..end]).map_or_else(
            String::new,
            |(trim_start, trim_end)| {
                self.source[text_start + trim_start..text_start + trim_end].to_owned()
            },
        );
        Ok(MermaidComment {
            text,
            span: Span::new(start, end),
        })
    }
}

struct MermaidDirectiveParser<'source> {
    source: &'source str,
}

impl<'source> MermaidDirectiveParser<'source> {
    fn new(source: &'source str) -> Self {
        Self { source }
    }

    fn parse(&self) -> Result<MermaidDirective, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedDirective,
                span: Span::new(0, 0),
            });
        };
        if !self.source[start..end].starts_with("%%{") {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedDirective,
                span: Span::new(start, end),
            });
        }

        let body_start = start + 3;
        let Some(close_offset) = self.source[body_start..end].find("}%%") else {
            return Err(ParseError {
                kind: ParseErrorKind::UnterminatedDirective,
                span: Span::new(start, end),
            });
        };
        let body_end = body_start + close_offset;
        let directive_end = body_end + 3;
        if trim_ascii_range(&self.source[directive_end..end]).is_some() {
            return Err(ParseError {
                kind: ParseErrorKind::TrailingInput,
                span: Span::new(directive_end, end),
            });
        }

        let (raw, key) = if let Some((trim_start, trim_end)) =
            trim_ascii_range(&self.source[body_start..body_end])
        {
            let raw_start = body_start + trim_start;
            let raw_end = body_start + trim_end;
            (
                self.source[raw_start..raw_end].to_owned(),
                directive_key(self.source, raw_start, raw_end),
            )
        } else {
            (String::new(), None)
        };

        Ok(MermaidDirective {
            raw,
            key,
            span: Span::new(start, directive_end),
        })
    }
}

impl<'source> FlowClassApplyParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<FlowClassApply, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedClassStatement,
                span: Span::new(0, 0),
            });
        };
        let keyword = "class";
        if !has_keyword(self.source, start, keyword) {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedClassStatement,
                span: Span::new(start, end),
            });
        }

        let rest_start = start + keyword.len();
        let Some((rest_trim_start, rest_trim_end)) =
            trim_ascii_range(&self.source[rest_start..end])
        else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedClassNode,
                span: Span::new(rest_start, end),
            });
        };
        let rest_start = rest_start + rest_trim_start;
        let rest_end = start + keyword.len() + rest_trim_end;
        let rest = &self.source[rest_start..rest_end];
        let Some(class_start) = rest.rfind(|value: char| value.is_ascii_whitespace()) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedClassName,
                span: Span::new(rest_start, rest_end),
            });
        };

        let node_ids = parse_csv_identifiers(
            self.source,
            rest_start,
            rest_start + class_start,
            ParseErrorKind::ExpectedClassNode,
        )?;
        let class_ids = parse_flexible_identifiers(
            self.source,
            rest_start + class_start,
            rest_end,
            ParseErrorKind::ExpectedClassName,
        )?;
        Ok(FlowClassApply {
            node_ids,
            class_ids,
            span: Span::new(start, end),
        })
    }
}

impl<'source> FlowEdgeParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
            cursor: 0,
        }
    }

    fn parse(&mut self) -> Result<FlowEdge, ParseError> {
        let mut from_parser = FlowNodeParser {
            source: self.source,
            cursor: self.cursor,
        };
        let from = from_parser.parse_expr()?;
        self.cursor = from_parser.cursor;
        self.skip_ws();

        let edge_start = self.cursor;
        for edge_end in edge_start + 2..=self.source.len() {
            let Some((link, label)) = parse_flow_edge_link(self.source, edge_start, edge_end)
            else {
                continue;
            };
            let mut to_parser = FlowNodeParser {
                source: self.source,
                cursor: edge_end,
            };
            let Ok(to) = to_parser.parse_expr() else {
                continue;
            };
            to_parser.skip_ws();
            if to_parser.peek_byte() == Some(b';') {
                to_parser.cursor += 1;
                to_parser.skip_ws();
            }
            if to_parser.cursor != self.source.len() {
                continue;
            }
            return Ok(FlowEdge {
                span: Span::new(from.span.start, to.span.end),
                from,
                to,
                link,
                label,
            });
        }

        Err(ParseError {
            kind: ParseErrorKind::ExpectedFlowEdge,
            span: Span::new(edge_start, edge_start),
        })
    }

    fn skip_ws(&mut self) {
        while matches!(self.source.as_bytes().get(self.cursor), Some(b' ' | b'\t')) {
            self.cursor += 1;
        }
    }
}

struct FlowSubgraphParser<'source> {
    source: &'source str,
    cursor: usize,
}

impl<'source> FlowSubgraphParser<'source> {
    fn new(source: &'source str) -> Self {
        Self { source, cursor: 0 }
    }

    fn parse(&mut self) -> Result<FlowSubgraph, ParseError> {
        self.skip_blank_lines();
        let subgraph = self.parse_subgraph()?;
        self.skip_blank_lines();
        if self.cursor != self.source.len() {
            return Err(ParseError {
                kind: ParseErrorKind::TrailingInput,
                span: Span::new(self.cursor, self.source.len()),
            });
        }
        Ok(subgraph)
    }

    fn parse_subgraph(&mut self) -> Result<FlowSubgraph, ParseError> {
        let header = self.current_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedSubgraphHeader,
            span: Span::new(self.cursor, self.cursor),
        })?;
        let (mut subgraph, start) = parse_subgraph_header(self.source, header)?;
        self.cursor = header.next;

        loop {
            let Some(line) = self.current_line() else {
                return Err(ParseError {
                    kind: ParseErrorKind::UnterminatedSubgraph,
                    span: Span::new(start, self.source.len()),
                });
            };
            let Some((trim_start, trim_end)) = trim_ascii_range(line.text) else {
                self.cursor = line.next;
                continue;
            };
            let absolute_start = line.start + trim_start;
            let absolute_end = line.start + trim_end;
            let trimmed = &self.source[absolute_start..absolute_end];

            if trimmed == "end" {
                subgraph.span = Span::new(start, absolute_end);
                self.cursor = line.next;
                return Ok(subgraph);
            }
            if trimmed.starts_with("subgraph") {
                let nested = self.parse_subgraph()?;
                subgraph.statements.push(FlowStatement::Subgraph(nested));
                continue;
            }
            if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
                subgraph
                    .statements
                    .push(FlowStatement::Directive(shift_directive(
                        directive,
                        absolute_start,
                    )));
                self.cursor = line.next;
                continue;
            }
            if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
                subgraph
                    .statements
                    .push(FlowStatement::Comment(shift_comment(
                        comment,
                        absolute_start,
                    )));
                self.cursor = line.next;
                continue;
            }
            if let Some(direction) = parse_direction_statement(trimmed, absolute_start)? {
                subgraph.direction = Some(direction);
                self.cursor = line.next;
                continue;
            }
            if let Ok(class_def) = Parser::parse_flow_class_def(trimmed) {
                subgraph
                    .statements
                    .push(FlowStatement::ClassDef(shift_class_def(
                        class_def,
                        absolute_start,
                    )));
                self.cursor = line.next;
                continue;
            }
            if let Ok(class_apply) = Parser::parse_flow_class_apply(trimmed) {
                subgraph
                    .statements
                    .push(FlowStatement::ClassApply(shift_class_apply(
                        class_apply,
                        absolute_start,
                    )));
                self.cursor = line.next;
                continue;
            }
            if let Ok(edge) = Parser::parse_flow_edge(trimmed) {
                subgraph
                    .statements
                    .push(FlowStatement::Edge(Box::new(shift_edge(
                        edge,
                        absolute_start,
                    ))));
                self.cursor = line.next;
                continue;
            }
            if let Ok(node) = Parser::parse_flow_node(trimmed) {
                subgraph
                    .statements
                    .push(FlowStatement::Node(shift_node(node, absolute_start)));
                self.cursor = line.next;
                continue;
            }
            return Err(ParseError {
                kind: ParseErrorKind::UnknownFlowStatement,
                span: Span::new(absolute_start, absolute_end),
            });
        }
    }

    fn skip_blank_lines(&mut self) {
        while let Some(line) = self.current_line() {
            if trim_ascii_range(line.text).is_some() {
                break;
            }
            self.cursor = line.next;
        }
    }

    fn current_line(&self) -> Option<SourceLine<'source>> {
        if self.cursor >= self.source.len() {
            return None;
        }
        let rest = &self.source[self.cursor..];
        let relative_end = rest.find(['\n', '\r']).unwrap_or(rest.len());
        let end = self.cursor + relative_end;
        let next = if end == self.source.len() {
            end
        } else if self.source[end..].starts_with("\r\n") {
            end + 2
        } else {
            end + 1
        };
        Some(SourceLine {
            start: self.cursor,
            text: &self.source[self.cursor..end],
            next,
        })
    }
}

#[derive(Debug, Clone, Copy)]
struct SourceLine<'source> {
    start: usize,
    text: &'source str,
    next: usize,
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
        let node = self.parse_expr()?;
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
        Ok(node)
    }

    fn parse_expr(&mut self) -> Result<FlowNode, ParseError> {
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
        label_from_body(self.source, start, end)
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

fn trimmed_statement_bounds(source: &str) -> Option<(usize, usize)> {
    let line = first_line(source);
    let (start, mut end) = trim_ascii_range(line)?;
    if line.as_bytes().get(end - 1) == Some(&b';') {
        end -= 1;
        let (inner_start, inner_end) = trim_ascii_range(&line[start..end])?;
        return Some((start + inner_start, start + inner_end));
    }
    Some((start, end))
}

fn has_keyword(source: &str, start: usize, keyword: &str) -> bool {
    source[start..].starts_with(keyword)
        && source
            .as_bytes()
            .get(start + keyword.len())
            .is_some_and(u8::is_ascii_whitespace)
}

fn parse_csv_identifiers(
    source: &str,
    start: usize,
    end: usize,
    error_kind: ParseErrorKind,
) -> Result<Vec<Spanned<String>>, ParseError> {
    let mut values = Vec::new();
    let mut part_start = start;
    while part_start <= end {
        let part_end = source[part_start..end]
            .find(',')
            .map_or(end, |offset| part_start + offset);
        push_identifier(source, part_start, part_end, error_kind, &mut values)?;
        if part_end == end {
            break;
        }
        part_start = part_end + 1;
    }
    Ok(values)
}

fn parse_flexible_identifiers(
    source: &str,
    start: usize,
    end: usize,
    error_kind: ParseErrorKind,
) -> Result<Vec<Spanned<String>>, ParseError> {
    let mut values = Vec::new();
    let mut cursor = start;
    while cursor < end {
        while cursor < end && matches!(source.as_bytes().get(cursor), Some(b',' | b' ' | b'\t')) {
            cursor += 1;
        }
        if cursor == end {
            break;
        }
        let value_start = cursor;
        while cursor < end && !matches!(source.as_bytes().get(cursor), Some(b',' | b' ' | b'\t')) {
            cursor += 1;
        }
        push_identifier(source, value_start, cursor, error_kind, &mut values)?;
    }
    if values.is_empty() {
        return Err(ParseError {
            kind: error_kind,
            span: Span::new(start, end),
        });
    }
    Ok(values)
}

fn push_identifier(
    source: &str,
    start: usize,
    end: usize,
    error_kind: ParseErrorKind,
    values: &mut Vec<Spanned<String>>,
) -> Result<(), ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: error_kind,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let value = &source[absolute_start..absolute_end];
    if !is_identifier(value) {
        return Err(ParseError {
            kind: error_kind,
            span: Span::new(absolute_start, absolute_end),
        });
    }
    values.push(Spanned::new(
        value.to_owned(),
        Span::new(absolute_start, absolute_end),
    ));
    Ok(())
}

fn is_identifier(value: &str) -> bool {
    let mut bytes = value.as_bytes().iter();
    let Some(first) = bytes.next() else {
        return false;
    };
    (first.is_ascii_alphanumeric() || *first == b'_')
        && bytes.all(|value| value.is_ascii_alphanumeric() || *value == b'_' || *value == b'-')
}

fn parse_style_declarations(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<FlowStyleDeclaration>, ParseError> {
    let mut values = Vec::new();
    let mut part_start = start;
    while part_start <= end {
        let part_end = find_unescaped_comma(source, part_start, end).unwrap_or(end);
        if let Some(value) = parse_style_declaration(source, part_start, part_end)? {
            values.push(value);
        }
        if part_end == end {
            break;
        }
        part_start = part_end + 1;
    }
    if values.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedStyleDeclaration,
            span: Span::new(start, end),
        });
    }
    Ok(values)
}

fn parse_style_declaration(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Option<FlowStyleDeclaration>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Ok(None);
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let Some(colon) = source[absolute_start..absolute_end].find(':') else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedStyleDeclaration,
            span: Span::new(absolute_start, absolute_end),
        });
    };
    let key_start = absolute_start;
    let key_end = absolute_start + colon;
    let value_start = key_end + 1;
    let Some((key_trim_start, key_trim_end)) = trim_ascii_range(&source[key_start..key_end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedStyleDeclaration,
            span: Span::new(absolute_start, absolute_end),
        });
    };
    let Some((value_trim_start, value_trim_end)) =
        trim_ascii_range(&source[value_start..absolute_end])
    else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedStyleDeclaration,
            span: Span::new(absolute_start, absolute_end),
        });
    };

    let key_absolute_start = key_start + key_trim_start;
    let key_absolute_end = key_start + key_trim_end;
    let value_absolute_start = value_start + value_trim_start;
    let value_absolute_end = value_start + value_trim_end;
    let value = source[value_absolute_start..value_absolute_end].replace(r"\,", ",");
    Ok(Some(FlowStyleDeclaration {
        key: Spanned::new(
            source[key_absolute_start..key_absolute_end].to_owned(),
            Span::new(key_absolute_start, key_absolute_end),
        ),
        value: Spanned::new(value, Span::new(value_absolute_start, value_absolute_end)),
        span: Span::new(absolute_start, absolute_end),
    }))
}

fn find_unescaped_comma(source: &str, start: usize, end: usize) -> Option<usize> {
    let bytes = source.as_bytes();
    let mut cursor = start;
    while cursor < end {
        if bytes[cursor] == b',' && (cursor == start || bytes[cursor - 1] != b'\\') {
            return Some(cursor);
        }
        cursor += 1;
    }
    None
}

fn directive_key(source: &str, start: usize, end: usize) -> Option<Spanned<String>> {
    let colon = source[start..end].find(':')?;
    let key_end = start + colon;
    let (trim_start, trim_end) = trim_ascii_range(&source[start..key_end])?;
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let key = &source[absolute_start..absolute_end];
    is_identifier(key)
        .then(|| Spanned::new(key.to_owned(), Span::new(absolute_start, absolute_end)))
}

fn parse_subgraph_header(
    source: &str,
    line: SourceLine<'_>,
) -> Result<(FlowSubgraph, usize), ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(line.text) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedSubgraphHeader,
            span: Span::new(line.start, line.start),
        });
    };
    let absolute_start = line.start + trim_start;
    let absolute_end = line.start + trim_end;
    let trimmed = &source[absolute_start..absolute_end];
    let keyword = "subgraph";
    if !trimmed.starts_with(keyword)
        || !trimmed
            .as_bytes()
            .get(keyword.len())
            .is_some_and(u8::is_ascii_whitespace)
    {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedSubgraphHeader,
            span: Span::new(absolute_start, absolute_end),
        });
    }

    let rest_start = absolute_start + keyword.len();
    let Some((rest_trim_start, rest_trim_end)) =
        trim_ascii_range(&source[rest_start..absolute_end])
    else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedSubgraphId,
            span: Span::new(rest_start, absolute_end),
        });
    };
    let rest_absolute_start = rest_start + rest_trim_start;
    let rest_absolute_end = rest_start + rest_trim_end;
    let rest = &source[rest_absolute_start..rest_absolute_end];

    let (id, label) = if rest.ends_with(']') {
        if let Some(label_open) = rest.find('[') {
            let id_source = &rest[..label_open];
            let Some((id_start, id_end)) = trim_ascii_range(id_source) else {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedSubgraphId,
                    span: Span::new(rest_absolute_start, rest_absolute_start + label_open),
                });
            };
            let label_start = rest_absolute_start + label_open + 1;
            let label_end = rest_absolute_end - 1;
            (
                Spanned::new(
                    id_source[id_start..id_end].to_owned(),
                    Span::new(rest_absolute_start + id_start, rest_absolute_start + id_end),
                ),
                label_from_trimmed(source, label_start, label_end),
            )
        } else {
            subgraph_id_from_rest(rest, rest_absolute_start)?
        }
    } else {
        subgraph_id_from_rest(rest, rest_absolute_start)?
    };

    Ok((
        FlowSubgraph {
            id,
            label,
            direction: None,
            statements: Vec::new(),
            span: Span::new(absolute_start, absolute_end),
        },
        absolute_start,
    ))
}

fn subgraph_id_from_rest(
    rest: &str,
    rest_absolute_start: usize,
) -> Result<(Spanned<String>, Option<Label>), ParseError> {
    let Some((id_start, id_end)) = trim_ascii_range(rest) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedSubgraphId,
            span: Span::new(rest_absolute_start, rest_absolute_start),
        });
    };
    Ok((
        Spanned::new(
            rest[id_start..id_end].to_owned(),
            Span::new(rest_absolute_start + id_start, rest_absolute_start + id_end),
        ),
        None,
    ))
}

fn parse_direction_statement(
    source: &str,
    absolute_start: usize,
) -> Result<Option<Spanned<Direction>>, ParseError> {
    let keyword = "direction";
    if !source.starts_with(keyword) {
        return Ok(None);
    }
    let after_keyword = &source[keyword.len()..];
    if !after_keyword
        .as_bytes()
        .first()
        .is_some_and(u8::is_ascii_whitespace)
    {
        return Ok(None);
    }
    let Some((direction_start, direction_end)) = trim_ascii_range(after_keyword) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedFlowchartDirection,
            span: Span::new(
                absolute_start + keyword.len(),
                absolute_start + source.len(),
            ),
        });
    };
    let direction_source = &after_keyword[direction_start..direction_end];
    let Some(direction) = Direction::from_mermaid(direction_source) else {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownFlowchartDirection,
            span: Span::new(
                absolute_start + keyword.len() + direction_start,
                absolute_start + keyword.len() + direction_end,
            ),
        });
    };
    Ok(Some(Spanned::new(
        direction,
        Span::new(
            absolute_start + keyword.len() + direction_start,
            absolute_start + keyword.len() + direction_end,
        ),
    )))
}

fn shift_span(span: Span, offset: usize) -> Span {
    Span::new(span.start + offset, span.end + offset)
}

fn shift_spanned<T>(spanned: Spanned<T>, offset: usize) -> Spanned<T> {
    Spanned::new(spanned.value, shift_span(spanned.span, offset))
}

fn shift_label(label: Label, offset: usize) -> Label {
    Label {
        text: label.text,
        kind: label.kind,
        span: shift_span(label.span, offset),
    }
}

fn shift_node(node: FlowNode, offset: usize) -> FlowNode {
    FlowNode {
        id: shift_spanned(node.id, offset),
        label: node.label.map(|label| shift_label(label, offset)),
        shape: shift_spanned(node.shape, offset),
        span: shift_span(node.span, offset),
    }
}

fn shift_edge(edge: FlowEdge, offset: usize) -> FlowEdge {
    FlowEdge {
        from: shift_node(edge.from, offset),
        to: shift_node(edge.to, offset),
        link: shift_spanned(edge.link, offset),
        label: edge.label.map(|label| shift_label(label, offset)),
        span: shift_span(edge.span, offset),
    }
}

fn shift_style_declaration(style: FlowStyleDeclaration, offset: usize) -> FlowStyleDeclaration {
    FlowStyleDeclaration {
        key: shift_spanned(style.key, offset),
        value: shift_spanned(style.value, offset),
        span: shift_span(style.span, offset),
    }
}

fn shift_class_def(class_def: FlowClassDef, offset: usize) -> FlowClassDef {
    FlowClassDef {
        class_ids: class_def
            .class_ids
            .into_iter()
            .map(|class_id| shift_spanned(class_id, offset))
            .collect(),
        styles: class_def
            .styles
            .into_iter()
            .map(|style| shift_style_declaration(style, offset))
            .collect(),
        span: shift_span(class_def.span, offset),
    }
}

fn shift_class_apply(class_apply: FlowClassApply, offset: usize) -> FlowClassApply {
    FlowClassApply {
        node_ids: class_apply
            .node_ids
            .into_iter()
            .map(|node_id| shift_spanned(node_id, offset))
            .collect(),
        class_ids: class_apply
            .class_ids
            .into_iter()
            .map(|class_id| shift_spanned(class_id, offset))
            .collect(),
        span: shift_span(class_apply.span, offset),
    }
}

fn shift_comment(comment: MermaidComment, offset: usize) -> MermaidComment {
    MermaidComment {
        text: comment.text,
        span: shift_span(comment.span, offset),
    }
}

fn shift_directive(directive: MermaidDirective, offset: usize) -> MermaidDirective {
    MermaidDirective {
        raw: directive.raw,
        key: directive.key.map(|key| shift_spanned(key, offset)),
        span: shift_span(directive.span, offset),
    }
}

fn parse_flow_edge_link(
    source: &str,
    start: usize,
    end: usize,
) -> Option<(Spanned<FlowEdgeLink>, Option<Label>)> {
    let segment = &source[start..end];
    let (trim_start, trim_end) = trim_ascii_range(segment)?;
    let raw_start = start + trim_start;
    let raw_end = start + trim_end;
    let raw = &source[raw_start..raw_end];

    if let Some(pipe_start) = raw.find('|')
        && pipe_start < raw.len() - 1
        && raw.ends_with('|')
    {
        let link = parse_unlabeled_edge_operator(source, raw_start, raw_start + pipe_start)?;
        let label = label_from_trimmed(source, raw_start + pipe_start + 1, raw_end - 1)?;
        return Some((link, Some(label)));
    }
    if let Some(link) = parse_wrapped_label_edge(source, raw_start, raw_end) {
        return Some(link);
    }
    parse_unlabeled_edge_operator(source, raw_start, raw_end).map(|link| (link, None))
}

fn parse_unlabeled_edge_operator(
    source: &str,
    start: usize,
    end: usize,
) -> Option<Spanned<FlowEdgeLink>> {
    let raw = &source[start..end];
    let bytes = raw.as_bytes();
    if bytes.is_empty() {
        return None;
    }

    let (arrow_start, core_start) = match bytes.first() {
        Some(b'<') => (ArrowHead::Arrow, 1),
        Some(b'o') => (ArrowHead::Circle, 1),
        Some(b'x') => (ArrowHead::Cross, 1),
        _ => (ArrowHead::None, 0),
    };
    let (arrow_end, core_end) = match bytes.last() {
        Some(b'>') => (ArrowHead::Arrow, raw.len() - 1),
        Some(b'o') => (ArrowHead::Circle, raw.len() - 1),
        Some(b'x') => (ArrowHead::Cross, raw.len() - 1),
        _ => (ArrowHead::None, raw.len()),
    };
    if core_start >= core_end {
        return None;
    }

    let core = &raw[core_start..core_end];
    let headed = arrow_start != ArrowHead::None || arrow_end != ArrowHead::None;
    let (stroke, min_length) = if core.as_bytes().iter().all(|value| *value == b'-') {
        (
            FlowEdgeStroke::Normal,
            min_length_from_count(core.len(), headed)?,
        )
    } else if core.as_bytes().iter().all(|value| *value == b'=') {
        (
            FlowEdgeStroke::Thick,
            min_length_from_count(core.len(), headed)?,
        )
    } else if let Some(min_length) = dotted_min_length(core) {
        (FlowEdgeStroke::Dotted, min_length)
    } else if !headed && core.as_bytes().iter().all(|value| *value == b'~') && core.len() >= 3 {
        (FlowEdgeStroke::Invisible, (core.len() - 2) as u16)
    } else {
        return None;
    };

    Some(Spanned::new(
        FlowEdgeLink {
            stroke,
            arrow_start,
            arrow_end,
            min_length,
        },
        Span::new(start, end),
    ))
}

fn parse_wrapped_label_edge(
    source: &str,
    start: usize,
    end: usize,
) -> Option<(Spanned<FlowEdgeLink>, Option<Label>)> {
    parse_wrapped_repeated_label_edge(source, start, end, "--", b'-', FlowEdgeStroke::Normal)
        .or_else(|| {
            parse_wrapped_repeated_label_edge(source, start, end, "==", b'=', FlowEdgeStroke::Thick)
        })
        .or_else(|| parse_wrapped_dotted_label_edge(source, start, end))
}

fn parse_wrapped_repeated_label_edge(
    source: &str,
    start: usize,
    end: usize,
    prefix: &str,
    repeat: u8,
    stroke: FlowEdgeStroke,
) -> Option<(Spanned<FlowEdgeLink>, Option<Label>)> {
    let raw = &source[start..end];
    if !raw.starts_with(prefix) {
        return None;
    }
    let (trailer_start, arrow_end, min_length) = repeated_trailer(raw, repeat)?;
    let label_start = start + prefix.len();
    let label_end = start + trailer_start;
    if label_start >= label_end {
        return None;
    }
    let label = label_from_trimmed(source, label_start, label_end)?;
    Some((
        Spanned::new(
            FlowEdgeLink {
                stroke,
                arrow_start: ArrowHead::None,
                arrow_end,
                min_length,
            },
            Span::new(start, end),
        ),
        Some(label),
    ))
}

fn parse_wrapped_dotted_label_edge(
    source: &str,
    start: usize,
    end: usize,
) -> Option<(Spanned<FlowEdgeLink>, Option<Label>)> {
    let raw = &source[start..end];
    if !raw.starts_with("-.") {
        return None;
    }
    let (trailer_start, arrow_end, min_length) = dotted_trailer(raw)?;
    if start + 2 >= start + trailer_start {
        return None;
    }
    let label = label_from_trimmed(source, start + 2, start + trailer_start)?;
    Some((
        Spanned::new(
            FlowEdgeLink {
                stroke: FlowEdgeStroke::Dotted,
                arrow_start: ArrowHead::None,
                arrow_end,
                min_length,
            },
            Span::new(start, end),
        ),
        Some(label),
    ))
}

fn repeated_trailer(raw: &str, repeat: u8) -> Option<(usize, ArrowHead, u16)> {
    let bytes = raw.as_bytes();
    let (arrow_end, mut end) = match bytes.last() {
        Some(b'>') => (ArrowHead::Arrow, raw.len() - 1),
        Some(b'o') => (ArrowHead::Circle, raw.len() - 1),
        Some(b'x') => (ArrowHead::Cross, raw.len() - 1),
        _ => (ArrowHead::None, raw.len()),
    };
    while end > 0 && bytes[end - 1] == repeat {
        end -= 1;
    }
    let count = match arrow_end {
        ArrowHead::None => raw.len() - end,
        _ => raw.len() - 1 - end,
    };
    Some((
        end,
        arrow_end,
        min_length_from_count(count, arrow_end != ArrowHead::None)?,
    ))
}

fn dotted_trailer(raw: &str) -> Option<(usize, ArrowHead, u16)> {
    let bytes = raw.as_bytes();
    let (arrow_end, end) = match bytes.last() {
        Some(b'>') => (ArrowHead::Arrow, raw.len() - 1),
        Some(b'o') => (ArrowHead::Circle, raw.len() - 1),
        Some(b'x') => (ArrowHead::Cross, raw.len() - 1),
        _ => (ArrowHead::None, raw.len()),
    };
    if end == 0 || bytes[end - 1] != b'-' {
        return None;
    }
    let dash = end - 1;
    let mut start = dash;
    while start > 0 && bytes[start - 1] == b'.' {
        start -= 1;
    }
    let dot_count = dash - start;
    (dot_count > 0).then_some((start, arrow_end, dot_count as u16))
}

fn min_length_from_count(count: usize, headed: bool) -> Option<u16> {
    let baseline = if headed { 1 } else { 2 };
    if count > baseline {
        Some((count - baseline) as u16)
    } else {
        None
    }
}

fn dotted_min_length(core: &str) -> Option<u16> {
    let bytes = core.as_bytes();
    if bytes.len() < 3 || bytes.first() != Some(&b'-') || bytes.last() != Some(&b'-') {
        return None;
    }
    let dot_count = bytes[1..bytes.len() - 1]
        .iter()
        .filter(|value| **value == b'.')
        .count();
    (dot_count == bytes.len() - 2 && dot_count > 0).then_some(dot_count as u16)
}

fn label_from_trimmed(source: &str, start: usize, end: usize) -> Option<Label> {
    let (trim_start, trim_end) = trim_ascii_range(&source[start..end])?;
    Some(label_from_body(
        source,
        start + trim_start,
        start + trim_end,
    ))
}

fn label_from_body(source: &str, start: usize, end: usize) -> Label {
    let raw = &source[start..end];
    if raw.len() >= 2
        && raw.as_bytes().first() == Some(&b'"')
        && raw.as_bytes().last() == Some(&b'"')
    {
        let quoted_start = start + 1;
        let quoted_end = end - 1;
        let quoted = &source[quoted_start..quoted_end];
        if quoted.len() >= 2
            && quoted.as_bytes().first() == Some(&b'`')
            && quoted.as_bytes().last() == Some(&b'`')
        {
            return Label {
                text: source[quoted_start + 1..quoted_end - 1].to_owned(),
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

#[cfg(test)]
mod tests {
    use super::{
        FlowchartHeaderToken, FlowchartHeaderTokenKind, ParseError, ParseErrorKind, Parser,
    };
    use crate::ast::{
        ArrowHead, Direction, FlowEdgeStroke, FlowShape, FlowStatement, FlowchartDirective,
        LabelKind, Span,
    };

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

    #[test]
    fn parses_basic_flow_edges() {
        let cases = [
            (
                "A --> B",
                FlowEdgeStroke::Normal,
                ArrowHead::None,
                ArrowHead::Arrow,
                1,
            ),
            (
                "A --- B",
                FlowEdgeStroke::Normal,
                ArrowHead::None,
                ArrowHead::None,
                1,
            ),
            (
                "A ----> B",
                FlowEdgeStroke::Normal,
                ArrowHead::None,
                ArrowHead::Arrow,
                3,
            ),
            (
                "A ==> B",
                FlowEdgeStroke::Thick,
                ArrowHead::None,
                ArrowHead::Arrow,
                1,
            ),
            (
                "A -.-> B",
                FlowEdgeStroke::Dotted,
                ArrowHead::None,
                ArrowHead::Arrow,
                1,
            ),
            (
                "A ~~~ B",
                FlowEdgeStroke::Invisible,
                ArrowHead::None,
                ArrowHead::None,
                1,
            ),
        ];

        for (source, stroke, arrow_start, arrow_end, min_length) in cases {
            let edge = Parser::parse_flow_edge(source).unwrap();

            assert_eq!(edge.from.id.value, "A");
            assert_eq!(edge.to.id.value, "B");
            assert_eq!(edge.link.value.stroke, stroke);
            assert_eq!(edge.link.value.arrow_start, arrow_start);
            assert_eq!(edge.link.value.arrow_end, arrow_end);
            assert_eq!(edge.link.value.min_length, min_length);
        }
    }

    #[test]
    fn parses_labelled_flow_edges() {
        let cases = [
            ("A -- label --> B", FlowEdgeStroke::Normal, "label"),
            ("A -->|pipe label| B", FlowEdgeStroke::Normal, "pipe label"),
            ("A == thick ==> B", FlowEdgeStroke::Thick, "thick"),
            ("A -. dotted .-> B", FlowEdgeStroke::Dotted, "dotted"),
        ];

        for (source, stroke, label) in cases {
            let edge = Parser::parse_flow_edge(source).unwrap();

            assert_eq!(edge.link.value.stroke, stroke);
            assert_eq!(edge.link.value.arrow_end, ArrowHead::Arrow);
            assert_eq!(edge.label.unwrap().text, label);
        }
    }

    #[test]
    fn parses_circle_cross_and_bidirectional_edges() {
        let circle = Parser::parse_flow_edge("A --o B").unwrap();
        let cross = Parser::parse_flow_edge("A x--x B").unwrap();
        let bidirectional = Parser::parse_flow_edge("A <--> B").unwrap();

        assert_eq!(circle.link.value.arrow_end, ArrowHead::Circle);
        assert_eq!(cross.link.value.arrow_start, ArrowHead::Cross);
        assert_eq!(cross.link.value.arrow_end, ArrowHead::Cross);
        assert_eq!(bidirectional.link.value.arrow_start, ArrowHead::Arrow);
        assert_eq!(bidirectional.link.value.arrow_end, ArrowHead::Arrow);
    }

    #[test]
    fn parses_flow_edges_with_inline_node_shapes() {
        let edge = Parser::parse_flow_edge("A[Start] --> B((End))").unwrap();

        assert_eq!(edge.from.label.unwrap().text, "Start");
        assert_eq!(edge.to.shape.value, FlowShape::Circle);
        assert_eq!(edge.to.label.unwrap().text, "End");
    }

    #[test]
    fn rejects_missing_flow_edge() {
        assert_eq!(
            Parser::parse_flow_edge("A B").unwrap_err().kind,
            ParseErrorKind::ExpectedFlowEdge,
        );
    }

    #[test]
    fn parses_subgraph_with_explicit_title() {
        let subgraph =
            Parser::parse_flow_subgraph("subgraph frontend [Frontend Services]\n    A --> B\nend")
                .unwrap();

        assert_eq!(subgraph.id.value, "frontend");
        assert_eq!(subgraph.label.unwrap().text, "Frontend Services");
        assert_eq!(subgraph.statements.len(), 1);
        let FlowStatement::Edge(edge) = &subgraph.statements[0] else {
            panic!("expected edge statement");
        };
        assert_eq!(edge.from.id.value, "A");
        assert_eq!(edge.to.id.value, "B");
    }

    #[test]
    fn parses_nested_subgraphs() {
        let subgraph = Parser::parse_flow_subgraph(
            "subgraph outer\n    subgraph inner\n        A\n    end\nend",
        )
        .unwrap();

        let FlowStatement::Subgraph(inner) = &subgraph.statements[0] else {
            panic!("expected nested subgraph");
        };
        assert_eq!(inner.id.value, "inner");
        let FlowStatement::Node(node) = &inner.statements[0] else {
            panic!("expected node statement");
        };
        assert_eq!(node.id.value, "A");
    }

    #[test]
    fn parses_subgraph_direction_override() {
        let subgraph = Parser::parse_flow_subgraph(
            "subgraph one [LR Group]\n    direction LR\n    A --> B\nend",
        )
        .unwrap();

        assert_eq!(subgraph.direction.unwrap().value, Direction::LeftRight);
        assert_eq!(subgraph.statements.len(), 1);
    }

    #[test]
    fn rejects_unterminated_subgraph() {
        assert_eq!(
            Parser::parse_flow_subgraph("subgraph one\n    A --> B")
                .unwrap_err()
                .kind,
            ParseErrorKind::UnterminatedSubgraph,
        );
    }

    #[test]
    fn parses_flow_class_def() {
        let class_def = Parser::parse_flow_class_def(
            "classDef warning fill:#f96,stroke:#333,stroke-width:2px;",
        )
        .unwrap();

        assert_eq!(class_def.class_ids[0].value, "warning");
        assert_eq!(class_def.styles.len(), 3);
        assert_eq!(class_def.styles[0].key.value, "fill");
        assert_eq!(class_def.styles[0].value.value, "#f96");
        assert_eq!(class_def.styles[2].key.value, "stroke-width");
    }

    #[test]
    fn parses_multiple_class_defs_and_escaped_style_commas() {
        let class_def = Parser::parse_flow_class_def(
            r"classDef first, second stroke-dasharray:5\,5,animation:fast",
        )
        .unwrap();

        assert_eq!(class_def.class_ids[0].value, "first");
        assert_eq!(class_def.class_ids[1].value, "second");
        assert_eq!(class_def.styles[0].value.value, "5,5");
        assert_eq!(class_def.styles[1].value.value, "fast");
    }

    #[test]
    fn parses_flow_class_apply() {
        let class_apply = Parser::parse_flow_class_apply("class A,B warning,active;").unwrap();

        assert_eq!(class_apply.node_ids[0].value, "A");
        assert_eq!(class_apply.node_ids[1].value, "B");
        assert_eq!(class_apply.class_ids[0].value, "warning");
        assert_eq!(class_apply.class_ids[1].value, "active");
    }

    #[test]
    fn parses_class_statements_inside_subgraph() {
        let subgraph = Parser::parse_flow_subgraph(
            "subgraph one\nclassDef warning fill:#f96\nclass A warning\nend",
        )
        .unwrap();

        let FlowStatement::ClassDef(class_def) = &subgraph.statements[0] else {
            panic!("expected classDef statement");
        };
        let FlowStatement::ClassApply(class_apply) = &subgraph.statements[1] else {
            panic!("expected class statement");
        };
        assert_eq!(class_def.class_ids[0].value, "warning");
        assert_eq!(class_apply.node_ids[0].value, "A");
    }

    #[test]
    fn rejects_class_def_without_styles() {
        assert_eq!(
            Parser::parse_flow_class_def("classDef warning")
                .unwrap_err()
                .kind,
            ParseErrorKind::ExpectedStyleDeclaration,
        );
    }

    #[test]
    fn rejects_class_apply_without_class_name() {
        assert_eq!(
            Parser::parse_flow_class_apply("class A").unwrap_err().kind,
            ParseErrorKind::ExpectedClassName,
        );
    }

    #[test]
    fn parses_mermaid_comment() {
        let comment = Parser::parse_mermaid_comment("  %% keep this").unwrap();

        assert_eq!(comment.text, "keep this");
        assert_eq!(comment.span, Span::new(2, 14));
    }

    #[test]
    fn parses_mermaid_directive() {
        let directive =
            Parser::parse_mermaid_directive("%%{ init: { 'theme': 'forest' } }%%").unwrap();

        assert_eq!(directive.raw, "init: { 'theme': 'forest' }");
        assert_eq!(directive.key.unwrap().value, "init");
        assert_eq!(directive.span, Span::new(0, 35));
    }

    #[test]
    fn stores_comments_and_directives_inside_subgraph() {
        let subgraph =
            Parser::parse_flow_subgraph("subgraph one\n%% keep\n%%{ animate: 'trace' }%%\nA\nend")
                .unwrap();

        let FlowStatement::Comment(comment) = &subgraph.statements[0] else {
            panic!("expected comment statement");
        };
        let FlowStatement::Directive(directive) = &subgraph.statements[1] else {
            panic!("expected directive statement");
        };
        assert_eq!(comment.text, "keep");
        assert_eq!(directive.key.as_ref().unwrap().value, "animate");
    }

    #[test]
    fn rejects_unterminated_directive() {
        assert_eq!(
            Parser::parse_mermaid_directive("%%{ init: {}")
                .unwrap_err()
                .kind,
            ParseErrorKind::UnterminatedDirective,
        );
    }
}
