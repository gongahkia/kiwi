use crate::ast::{
    ArrowHead, ClassAst, ClassHeader, ClassMember, ClassMemberAssignment, ClassMemberKind,
    ClassNode, ClassRelationship, ClassRelationshipLine, ClassRelationshipMarker, ClassStatement,
    Diagram, DiagramKind, DiagramMetadata, Direction, ErAst, ErAttribute, ErCardinality, ErEntity,
    ErHeader, ErRelationship, ErStatement, FlowClassApply, FlowClassDef, FlowEdge, FlowEdgeLink,
    FlowEdgeStroke, FlowNode, FlowShape, FlowStatement, FlowStyleDeclaration, FlowSubgraph,
    FlowchartAst, FlowchartDirective, FlowchartHeader, Label, LabelKind, MermaidComment,
    MermaidDirective, SequenceArrow, SequenceAst, SequenceAutoNumber, SequenceControlBlock,
    SequenceControlKind, SequenceHeader, SequenceMessage, SequenceNote, SequenceNotePlacement,
    SequenceParticipant, SequenceParticipantKind, SequenceStatement, Span, Spanned, StateAst,
    StateClassApply, StateDirective, StateHeader, StateNode, StateNodeKind, StateNote,
    StateStatement, StateTransition,
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
    ExpectedDiagramHeader,
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
    ExpectedSequenceHeader,
    UnknownSequenceStatement,
    ExpectedSequenceParticipant,
    ExpectedSequenceMessage,
    ExpectedStateHeader,
    UnknownStateStatement,
    ExpectedStateId,
    ExpectedStateTransition,
    ExpectedClassHeader,
    UnknownClassStatement,
    ExpectedClassMember,
    ExpectedClassRelationship,
    ExpectedErHeader,
    UnknownErStatement,
    ExpectedErEntity,
    ExpectedErAttribute,
    ExpectedErRelationship,
    TrailingInput,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError {
    pub kind: ParseErrorKind,
    pub span: Span,
}

impl Parser {
    pub fn parse_diagram(source: &str) -> Result<Diagram, ParseError> {
        DiagramParser::new(source).parse()
    }

    pub fn parse_flowchart(source: &str) -> Result<FlowchartAst, ParseError> {
        DiagramParser::new(source).parse_flowchart_only()
    }

    pub fn parse_sequence(source: &str) -> Result<SequenceAst, ParseError> {
        DiagramParser::new(source).parse_sequence_only()
    }

    pub fn parse_state(source: &str) -> Result<StateAst, ParseError> {
        DiagramParser::new(source).parse_state_only()
    }

    pub fn parse_class(source: &str) -> Result<ClassAst, ParseError> {
        DiagramParser::new(source).parse_class_only()
    }

    pub fn parse_er(source: &str) -> Result<ErAst, ParseError> {
        DiagramParser::new(source).parse_er_only()
    }

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

    pub fn parse_sequence_header(source: &str) -> Result<SequenceHeader, ParseError> {
        SequenceHeaderParser::new(source).parse()
    }

    pub fn parse_sequence_statement(source: &str) -> Result<SequenceStatement, ParseError> {
        SequenceStatementParser::new(source).parse()
    }

    pub fn parse_state_header(source: &str) -> Result<StateHeader, ParseError> {
        StateHeaderParser::new(source).parse()
    }

    pub fn parse_state_statement(source: &str) -> Result<StateStatement, ParseError> {
        StateStatementParser::new(source).parse()
    }

    pub fn parse_class_header(source: &str) -> Result<ClassHeader, ParseError> {
        ClassHeaderParser::new(source).parse()
    }

    pub fn parse_class_statement(source: &str) -> Result<ClassStatement, ParseError> {
        ClassStatementParser::new(source).parse()
    }

    pub fn parse_er_header(source: &str) -> Result<ErHeader, ParseError> {
        ErHeaderParser::new(source).parse()
    }

    pub fn parse_er_statement(source: &str) -> Result<ErStatement, ParseError> {
        ErStatementParser::new(source).parse()
    }
}

struct DiagramParser<'source> {
    source: &'source str,
    cursor: usize,
    directives: Vec<MermaidDirective>,
}

impl<'source> DiagramParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source,
            cursor: 0,
            directives: Vec::new(),
        }
    }

    fn parse(mut self) -> Result<Diagram, ParseError> {
        self.skip_preamble();
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedDiagramHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;

        if let Ok(flow_header) = Parser::parse_flowchart_header(header.text) {
            self.cursor = header.line.next;
            let ast =
                self.parse_flowchart_body(shift_flowchart_header(flow_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Flowchart(Box::new(ast))));
        }
        if let Ok(sequence_header) = Parser::parse_sequence_header(header.text) {
            self.cursor = header.line.next;
            let ast =
                self.parse_sequence_body(shift_sequence_header(sequence_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Sequence(Box::new(ast))));
        }
        if let Ok(state_header) = Parser::parse_state_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_state_body(shift_state_header(state_header, header.start))?;
            return Ok(self.diagram(DiagramKind::State(Box::new(ast))));
        }
        if let Ok(class_header) = Parser::parse_class_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_class_body(shift_class_header(class_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Class(Box::new(ast))));
        }
        if let Ok(er_header) = Parser::parse_er_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_er_body(shift_er_header(er_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Er(Box::new(ast))));
        }

        Err(ParseError {
            kind: ParseErrorKind::ExpectedDiagramHeader,
            span: Span::new(header.start, header.end),
        })
    }

    fn parse_flowchart_only(mut self) -> Result<FlowchartAst, ParseError> {
        self.skip_preamble();
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedFlowchartDirective,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let flow_header = Parser::parse_flowchart_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_flowchart_body(shift_flowchart_header(flow_header, header.start))
    }

    fn parse_sequence_only(mut self) -> Result<SequenceAst, ParseError> {
        self.skip_preamble();
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedSequenceHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let sequence_header = Parser::parse_sequence_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_sequence_body(shift_sequence_header(sequence_header, header.start))
    }

    fn parse_state_only(mut self) -> Result<StateAst, ParseError> {
        self.skip_preamble();
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedStateHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let state_header = Parser::parse_state_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_state_body(shift_state_header(state_header, header.start))
    }

    fn parse_class_only(mut self) -> Result<ClassAst, ParseError> {
        self.skip_preamble();
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedClassHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let class_header = Parser::parse_class_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_class_body(shift_class_header(class_header, header.start))
    }

    fn parse_er_only(mut self) -> Result<ErAst, ParseError> {
        self.skip_preamble();
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedErHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let er_header = Parser::parse_er_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_er_body(shift_er_header(er_header, header.start))
    }

    fn diagram(self, kind: DiagramKind) -> Diagram {
        Diagram {
            metadata: DiagramMetadata {
                title: None,
                accessibility_title: None,
                accessibility_description: None,
                span: Span::new(0, 0),
            },
            directives: self.directives,
            kind,
            span: Span::new(0, self.source.len()),
        }
    }

    fn skip_preamble(&mut self) {
        while let Some(line) = self.current_trimmed_line() {
            if let Ok(directive) = Parser::parse_mermaid_directive(line.text) {
                self.directives.push(shift_directive(directive, line.start));
                self.cursor = line.line.next;
                continue;
            }
            if Parser::parse_mermaid_comment(line.text).is_ok() {
                self.cursor = line.line.next;
                continue;
            }
            break;
        }
    }

    fn parse_flowchart_body(
        &mut self,
        header: FlowchartHeader,
    ) -> Result<FlowchartAst, ParseError> {
        let span = Span::new(header.span.start, self.source.len());
        let mut ast = FlowchartAst {
            header,
            statements: Vec::new(),
            nodes: Vec::new(),
            edges: Vec::new(),
            subgraphs: Vec::new(),
            classes: Vec::new(),
            span,
        };

        while let Some(line) = self.current_trimmed_line() {
            if line.text.starts_with("subgraph") {
                let (block_end, next_cursor) = collect_subgraph_span(self.source, line.start)?;
                let subgraph = Parser::parse_flow_subgraph(&self.source[line.start..block_end])?;
                push_flow_statement(
                    &mut ast,
                    FlowStatement::Subgraph(shift_subgraph(subgraph, line.start)),
                );
                self.cursor = next_cursor;
                continue;
            }

            for statement in parse_flow_document_statements(line.text, line.start)? {
                push_flow_statement(&mut ast, statement);
            }
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_sequence_body(&mut self, header: SequenceHeader) -> Result<SequenceAst, ParseError> {
        let mut ast = SequenceAst {
            header,
            statements: Vec::new(),
            participants: Vec::new(),
            boxes: Vec::new(),
            span: Span::new(header.span.start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            if line.text == "end" {
                self.cursor = line.line.next;
                continue;
            }
            let statement =
                shift_sequence_statement(Parser::parse_sequence_statement(line.text)?, line.start);
            if let SequenceStatement::Participant(participant) = &statement {
                ast.participants.push((**participant).clone());
            }
            ast.statements.push(statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_state_body(&mut self, header: StateHeader) -> Result<StateAst, ParseError> {
        let mut ast = StateAst {
            header,
            direction: None,
            statements: Vec::new(),
            states: Vec::new(),
            transitions: Vec::new(),
            classes: Vec::new(),
            span: Span::new(header.span.start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            if line.text == "}" {
                self.cursor = line.line.next;
                continue;
            }
            let statement =
                shift_state_statement(Parser::parse_state_statement(line.text)?, line.start);
            match &statement {
                StateStatement::State(state) | StateStatement::Composite(state) => {
                    ast.states.push((**state).clone());
                }
                StateStatement::Transition(transition) => {
                    ast.transitions.push((**transition).clone());
                }
                StateStatement::ClassDef(class_def) => ast.classes.push(class_def.clone()),
                StateStatement::Direction(direction) => ast.direction = Some(*direction),
                StateStatement::ClassApply(_)
                | StateStatement::Comment(_)
                | StateStatement::Directive(_) => {}
            }
            ast.statements.push(statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_class_body(&mut self, header: ClassHeader) -> Result<ClassAst, ParseError> {
        let mut ast = ClassAst {
            header,
            direction: None,
            statements: Vec::new(),
            classes: Vec::new(),
            relationships: Vec::new(),
            span: Span::new(header.span.start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            if is_class_block_header(line.text) {
                let class = self.parse_class_block(line)?;
                push_class_statement(&mut ast, ClassStatement::Class(Box::new(class)));
                continue;
            }
            if line.text == "}" {
                self.cursor = line.line.next;
                continue;
            }
            let statement =
                shift_class_statement(Parser::parse_class_statement(line.text)?, line.start);
            push_class_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_class_block(
        &mut self,
        header_line: TrimmedSourceLine<'source>,
    ) -> Result<ClassNode, ParseError> {
        let mut class = parse_class_declaration(
            header_line.text,
            0,
            header_line.text.len().saturating_sub(1),
            ParseErrorKind::ExpectedClassName,
        )?;
        class = shift_class_node(class, header_line.start);
        self.cursor = header_line.line.next;

        while let Some(line) = self.current_trimmed_line() {
            if line.text == "}" {
                class.span = Span::new(class.span.start, line.end);
                self.cursor = line.line.next;
                return Ok(class);
            }
            if let Some(annotation) = parse_class_annotation(line.text, 0, line.text.len()) {
                class.annotations.push(shift_label(annotation, line.start));
            } else {
                class.members.push(shift_class_member(
                    parse_class_member(line.text, 0, line.text.len())?,
                    line.start,
                ));
            }
            self.cursor = line.line.next;
        }

        Err(ParseError {
            kind: ParseErrorKind::ExpectedClassMember,
            span: Span::new(class.span.start, self.source.len()),
        })
    }

    fn parse_er_body(&mut self, header: ErHeader) -> Result<ErAst, ParseError> {
        let mut ast = ErAst {
            header,
            statements: Vec::new(),
            entities: Vec::new(),
            relationships: Vec::new(),
            span: Span::new(header.span.start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            if is_er_block_header(line.text) {
                let entity = self.parse_er_block(line)?;
                push_er_statement(&mut ast, ErStatement::Entity(Box::new(entity)));
                continue;
            }
            if line.text == "}" {
                self.cursor = line.line.next;
                continue;
            }
            let statement = shift_er_statement(Parser::parse_er_statement(line.text)?, line.start);
            push_er_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_er_block(
        &mut self,
        header_line: TrimmedSourceLine<'source>,
    ) -> Result<ErEntity, ParseError> {
        let mut entity = parse_er_entity_header(
            header_line.text,
            0,
            header_line.text.len().saturating_sub(1),
        )?;
        entity = shift_er_entity(entity, header_line.start);
        self.cursor = header_line.line.next;

        while let Some(line) = self.current_trimmed_line() {
            if line.text == "}" {
                entity.span = Span::new(entity.span.start, line.end);
                self.cursor = line.line.next;
                return Ok(entity);
            }
            entity.attributes.push(shift_er_attribute(
                parse_er_attribute(line.text, 0, line.text.len())?,
                line.start,
            ));
            self.cursor = line.line.next;
        }

        Err(ParseError {
            kind: ParseErrorKind::ExpectedErAttribute,
            span: Span::new(entity.span.start, self.source.len()),
        })
    }

    fn current_trimmed_line(&self) -> Option<TrimmedSourceLine<'source>> {
        let mut cursor = self.cursor;
        while let Some(line) = source_line(self.source, cursor) {
            let Some((trim_start, trim_end)) = trim_ascii_range(line.text) else {
                cursor = line.next;
                continue;
            };
            let start = line.start + trim_start;
            let end = line.start + trim_end;
            return Some(TrimmedSourceLine {
                line,
                start,
                end,
                text: &self.source[start..end],
            });
        }
        None
    }
}

#[derive(Debug, Clone, Copy)]
struct TrimmedSourceLine<'source> {
    line: SourceLine<'source>,
    start: usize,
    end: usize,
    text: &'source str,
}

fn parse_flow_document_statements(
    statement: &str,
    offset: usize,
) -> Result<Vec<FlowStatement>, ParseError> {
    if let Ok(directive) = Parser::parse_mermaid_directive(statement) {
        return Ok(vec![FlowStatement::Directive(shift_directive(
            directive, offset,
        ))]);
    }
    if let Ok(comment) = Parser::parse_mermaid_comment(statement) {
        return Ok(vec![FlowStatement::Comment(shift_comment(comment, offset))]);
    }
    if let Ok(class_def) = Parser::parse_flow_class_def(statement) {
        return Ok(vec![FlowStatement::ClassDef(shift_class_def(
            class_def, offset,
        ))]);
    }
    if let Ok(class_apply) = Parser::parse_flow_class_apply(statement) {
        return Ok(vec![FlowStatement::ClassApply(shift_class_apply(
            class_apply,
            offset,
        ))]);
    }
    if let Ok(edges) = parse_flow_edge_chain(statement)
        && edges.len() > 1
        && edges.iter().all(|edge| {
            edge.link.value.arrow_start != ArrowHead::None
                || edge.link.value.arrow_end != ArrowHead::None
        })
    {
        return Ok(edges
            .into_iter()
            .map(|edge| FlowStatement::Edge(Box::new(shift_edge(edge, offset))))
            .collect());
    }
    if let Ok(edge) = Parser::parse_flow_edge(statement) {
        return Ok(vec![FlowStatement::Edge(Box::new(shift_edge(
            edge, offset,
        )))]);
    }
    if let Ok(node) = Parser::parse_flow_node(statement) {
        return Ok(vec![FlowStatement::Node(shift_node(node, offset))]);
    }
    Err(ParseError {
        kind: ParseErrorKind::UnknownFlowStatement,
        span: Span::new(offset, offset + statement.len()),
    })
}

fn push_flow_statement(ast: &mut FlowchartAst, statement: FlowStatement) {
    match &statement {
        FlowStatement::Node(node) => ast.nodes.push(node.clone()),
        FlowStatement::Edge(edge) => ast.edges.push((**edge).clone()),
        FlowStatement::Subgraph(subgraph) => ast.subgraphs.push(subgraph.clone()),
        FlowStatement::ClassDef(class_def) => ast.classes.push(class_def.clone()),
        FlowStatement::ClassApply(_) | FlowStatement::Comment(_) | FlowStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_class_statement(ast: &mut ClassAst, statement: ClassStatement) {
    match &statement {
        ClassStatement::Class(class) => merge_class_node(&mut ast.classes, class),
        ClassStatement::Member(member) => {
            merge_class_member(&mut ast.classes, member);
        }
        ClassStatement::Relationship(relationship) => {
            ensure_class_id(&mut ast.classes, &relationship.from);
            ensure_class_id(&mut ast.classes, &relationship.to);
            ast.relationships.push((**relationship).clone());
        }
        ClassStatement::Direction(direction) => ast.direction = Some(*direction),
        ClassStatement::Comment(_) | ClassStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn merge_class_node(classes: &mut Vec<ClassNode>, class: &ClassNode) {
    if let Some(existing) = classes
        .iter_mut()
        .find(|value| value.id.value == class.id.value)
    {
        existing.annotations.extend(class.annotations.clone());
        existing.members.extend(class.members.clone());
        existing.span = Span::new(existing.span.start.min(class.span.start), class.span.end);
        return;
    }
    classes.push(class.clone());
}

fn merge_class_member(classes: &mut Vec<ClassNode>, member: &ClassMemberAssignment) {
    ensure_class_id(classes, &member.class_id);
    if let Some(class) = classes
        .iter_mut()
        .find(|value| value.id.value == member.class_id.value)
    {
        class.members.push(member.member.clone());
        class.span = Span::new(class.span.start.min(member.span.start), member.span.end);
    }
}

fn ensure_class_id(classes: &mut Vec<ClassNode>, id: &Spanned<String>) {
    if classes.iter().any(|class| class.id.value == id.value) {
        return;
    }
    classes.push(ClassNode {
        id: id.clone(),
        annotations: Vec::new(),
        members: Vec::new(),
        span: id.span,
    });
}

fn push_er_statement(ast: &mut ErAst, statement: ErStatement) {
    match &statement {
        ErStatement::Entity(entity) => merge_er_entity(&mut ast.entities, entity),
        ErStatement::Relationship(relationship) => {
            ensure_er_entity(&mut ast.entities, &relationship.from);
            ensure_er_entity(&mut ast.entities, &relationship.to);
            ast.relationships.push((**relationship).clone());
        }
        ErStatement::Comment(_) | ErStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn merge_er_entity(entities: &mut Vec<ErEntity>, entity: &ErEntity) {
    if let Some(existing) = entities
        .iter_mut()
        .find(|value| value.id.value == entity.id.value)
    {
        existing.attributes.extend(entity.attributes.clone());
        existing.span = Span::new(existing.span.start.min(entity.span.start), entity.span.end);
        return;
    }
    entities.push(entity.clone());
}

fn ensure_er_entity(entities: &mut Vec<ErEntity>, id: &Spanned<String>) {
    if entities.iter().any(|entity| entity.id.value == id.value) {
        return;
    }
    entities.push(ErEntity {
        id: id.clone(),
        attributes: Vec::new(),
        span: id.span,
    });
}

fn collect_subgraph_span(source: &str, start: usize) -> Result<(usize, usize), ParseError> {
    let mut cursor = start;
    let mut depth = 0usize;

    while let Some(line) = source_line(source, cursor) {
        if let Some((trim_start, trim_end)) = trim_ascii_range(line.text) {
            let absolute_start = line.start + trim_start;
            let absolute_end = line.start + trim_end;
            let trimmed = &source[absolute_start..absolute_end];
            if trimmed.starts_with("subgraph") {
                depth += 1;
            } else if trimmed == "end" {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    return Ok((absolute_end, line.next));
                }
            }
        }
        cursor = line.next;
    }

    Err(ParseError {
        kind: ParseErrorKind::UnterminatedSubgraph,
        span: Span::new(start, source.len()),
    })
}

struct FlowEdgeParser<'source> {
    source: &'source str,
    cursor: usize,
}

struct FlowClassDefParser<'source> {
    source: &'source str,
}

fn parse_flow_edge_chain(source: &str) -> Result<Vec<FlowEdge>, ParseError> {
    let source = first_line(source);
    let mut parser = FlowNodeParser { source, cursor: 0 };
    let mut from = parser.parse_expr()?;
    parser.skip_ws();
    let mut edges = Vec::new();

    while let Some(link) = parse_flow_edge_operator_at(source, parser.cursor) {
        parser.cursor = link.span.end;
        parser.skip_ws();

        let mut to_parser = FlowNodeParser {
            source,
            cursor: parser.cursor,
        };
        let to = to_parser.parse_expr()?;
        parser.cursor = to_parser.cursor;
        edges.push(FlowEdge {
            span: Span::new(from.span.start, to.span.end),
            from,
            to: to.clone(),
            link,
            label: None,
        });
        from = to;
        parser.skip_ws();
    }

    if edges.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedFlowEdge,
            span: Span::new(parser.cursor, parser.cursor),
        });
    }
    if parser.peek_byte() == Some(b';') {
        parser.cursor += 1;
        parser.skip_ws();
    }
    if parser.cursor != source.len() {
        return Err(ParseError {
            kind: ParseErrorKind::TrailingInput,
            span: Span::new(parser.cursor, source.len()),
        });
    }

    Ok(edges)
}

fn parse_flow_edge_operator_at(source: &str, start: usize) -> Option<Spanned<FlowEdgeLink>> {
    let mut best = None;
    for end in start + 2..=source.len() {
        if let Some(link) = parse_unlabeled_edge_operator(source, start, end) {
            best = Some(link);
        }
    }
    best
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

struct SequenceHeaderParser<'source> {
    source: &'source str,
}

impl<'source> SequenceHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<SequenceHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedSequenceHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "sequenceDiagram" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedSequenceHeader,
                span: Span::new(start, end),
            });
        }
        Ok(SequenceHeader {
            span: Span::new(start, end),
        })
    }
}

struct SequenceStatementParser<'source> {
    source: &'source str,
}

impl<'source> SequenceStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<SequenceStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownSequenceStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(SequenceStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(SequenceStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "participant") {
            return self.parse_participant(
                start,
                end,
                "participant",
                SequenceParticipantKind::Participant,
            );
        }
        if has_keyword(self.source, start, "actor") {
            return self.parse_participant(start, end, "actor", SequenceParticipantKind::Actor);
        }
        if trimmed.starts_with("Note ") {
            return self.parse_note(start, end);
        }
        if let Some(control) = self.parse_control(start, end)? {
            return Ok(control);
        }
        if let Some(message) = self.parse_message(start, end)? {
            return Ok(SequenceStatement::Message(Box::new(message)));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownSequenceStatement,
            span: Span::new(start, end),
        })
    }

    fn parse_participant(
        &self,
        start: usize,
        end: usize,
        keyword: &str,
        kind: SequenceParticipantKind,
    ) -> Result<SequenceStatement, ParseError> {
        let rest_start = start + keyword.len();
        let Some((rest_trim_start, rest_trim_end)) =
            trim_ascii_range(&self.source[rest_start..end])
        else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedSequenceParticipant,
                span: Span::new(rest_start, end),
            });
        };
        let rest_start = rest_start + rest_trim_start;
        let rest_end = start + keyword.len() + rest_trim_end;
        let rest = &self.source[rest_start..rest_end];
        let alias_marker = rest.find(" as ");
        let id_end = alias_marker.map_or(rest_end, |offset| rest_start + offset);
        let id = parse_single_identifier(
            self.source,
            rest_start,
            id_end,
            ParseErrorKind::ExpectedSequenceParticipant,
        )?;
        let alias = alias_marker.and_then(|offset| {
            let alias_start = rest_start + offset + 4;
            label_from_trimmed(self.source, alias_start, rest_end)
        });
        Ok(SequenceStatement::Participant(Box::new(
            SequenceParticipant {
                id,
                alias,
                kind,
                span: Span::new(start, end),
            },
        )))
    }

    fn parse_note(&self, start: usize, end: usize) -> Result<SequenceStatement, ParseError> {
        let after_note = start + "Note ".len();
        let note_source = &self.source[after_note..end];
        let (placement, participant_start) = if note_source.starts_with("over ") {
            (SequenceNotePlacement::Over, after_note + "over ".len())
        } else if note_source.starts_with("left of ") {
            (SequenceNotePlacement::LeftOf, after_note + "left of ".len())
        } else if note_source.starts_with("right of ") {
            (
                SequenceNotePlacement::RightOf,
                after_note + "right of ".len(),
            )
        } else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownSequenceStatement,
                span: Span::new(start, end),
            });
        };
        let Some(colon) = self.source[participant_start..end].find(':') else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownSequenceStatement,
                span: Span::new(start, end),
            });
        };
        let participant_end = participant_start + colon;
        let participants = parse_csv_identifiers(
            self.source,
            participant_start,
            participant_end,
            ParseErrorKind::ExpectedSequenceParticipant,
        )?;
        let Some(label) = label_from_trimmed(self.source, participant_end + 1, end) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownSequenceStatement,
                span: Span::new(participant_end + 1, end),
            });
        };
        Ok(SequenceStatement::Note(Box::new(SequenceNote {
            placement,
            participants,
            label,
            span: Span::new(start, end),
        })))
    }

    fn parse_control(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<SequenceStatement>, ParseError> {
        let controls = [
            ("loop", SequenceControlKind::Loop),
            ("alt", SequenceControlKind::Alt),
            ("opt", SequenceControlKind::Opt),
            ("par", SequenceControlKind::Par),
        ];
        for (keyword, kind) in controls {
            if !has_keyword(self.source, start, keyword) {
                continue;
            }
            let label = label_from_trimmed(self.source, start + keyword.len(), end);
            return Ok(Some(SequenceStatement::Control(Box::new(
                SequenceControlBlock {
                    kind,
                    label,
                    statements: Vec::new(),
                    span: Span::new(start, end),
                },
            ))));
        }
        Ok(None)
    }

    fn parse_message(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<SequenceMessage>, ParseError> {
        let Some((arrow_start, arrow, arrow_len)) = find_sequence_arrow(self.source, start, end)
        else {
            return Ok(None);
        };
        let from = parse_single_identifier(
            self.source,
            start,
            arrow_start,
            ParseErrorKind::ExpectedSequenceMessage,
        )?;
        let message_start = arrow_start + arrow_len;
        let Some(colon) = self.source[message_start..end].find(':') else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedSequenceMessage,
                span: Span::new(start, end),
            });
        };
        let to_end = message_start + colon;
        let to = parse_single_identifier(
            self.source,
            message_start,
            to_end,
            ParseErrorKind::ExpectedSequenceMessage,
        )?;
        let label = label_from_trimmed(self.source, to_end + 1, end);
        Ok(Some(SequenceMessage {
            from,
            to,
            arrow,
            label,
            span: Span::new(start, end),
        }))
    }
}

struct StateHeaderParser<'source> {
    source: &'source str,
}

impl<'source> StateHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<StateHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedStateHeader,
                span: Span::new(0, 0),
            });
        };
        let directive = match &self.source[start..end] {
            "stateDiagram" => StateDirective::StateDiagram,
            "stateDiagram-v2" => StateDirective::StateDiagramV2,
            _ => {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedStateHeader,
                    span: Span::new(start, end),
                });
            }
        };
        Ok(StateHeader {
            directive,
            span: Span::new(start, end),
        })
    }
}

struct StateStatementParser<'source> {
    source: &'source str,
}

impl<'source> StateStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<StateStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownStateStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(StateStatement::Directive(shift_directive(directive, start)));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(StateStatement::Comment(shift_comment(comment, start)));
        }
        if let Some(direction) = parse_direction_statement(trimmed, start)? {
            return Ok(StateStatement::Direction(direction));
        }
        if let Some(transition) = self.parse_transition(start, end)? {
            return Ok(StateStatement::Transition(Box::new(transition)));
        }
        if has_keyword(self.source, start, "state") {
            return self.parse_state(start, end);
        }
        if trimmed == "[*]" {
            return Ok(StateStatement::State(Box::new(StateNode {
                id: Spanned::new("[*]".to_owned(), Span::new(start, end)),
                label: None,
                kind: StateNodeKind::Start,
                descriptions: Vec::new(),
                note: None,
                children: Vec::new(),
                span: Span::new(start, end),
            })));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownStateStatement,
            span: Span::new(start, end),
        })
    }

    fn parse_transition(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<StateTransition>, ParseError> {
        let Some(arrow) = self.source[start..end].find("-->") else {
            return Ok(None);
        };
        let arrow_start = start + arrow;
        let from = parse_state_endpoint(
            self.source,
            start,
            arrow_start,
            ParseErrorKind::ExpectedStateTransition,
        )?;
        let after_arrow = arrow_start + 3;
        let label_start = self.source[after_arrow..end]
            .find(':')
            .map(|offset| after_arrow + offset);
        let to_end = label_start.unwrap_or(end);
        let to = parse_state_endpoint(
            self.source,
            after_arrow,
            to_end,
            ParseErrorKind::ExpectedStateTransition,
        )?;
        let label = label_start.and_then(|offset| label_from_trimmed(self.source, offset + 1, end));
        Ok(Some(StateTransition {
            from,
            to,
            label,
            span: Span::new(start, end),
        }))
    }

    fn parse_state(&self, start: usize, end: usize) -> Result<StateStatement, ParseError> {
        let rest_start = start + "state".len();
        let Some((rest_trim_start, rest_trim_end)) =
            trim_ascii_range(&self.source[rest_start..end])
        else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedStateId,
                span: Span::new(rest_start, end),
            });
        };
        let rest_start = rest_start + rest_trim_start;
        let rest_end = start + "state".len() + rest_trim_end;
        let rest = &self.source[rest_start..rest_end];
        let composite = rest.ends_with('{');
        let declaration_end = if composite { rest_end - 1 } else { rest_end };
        let (id, label, kind) = if rest.starts_with('"') {
            self.parse_aliased_state(rest_start, declaration_end)?
        } else {
            self.parse_named_state(rest_start, declaration_end)?
        };
        let node = StateNode {
            id,
            label,
            kind,
            descriptions: Vec::new(),
            note: None,
            children: Vec::new(),
            span: Span::new(start, end),
        };
        if composite {
            Ok(StateStatement::Composite(Box::new(node)))
        } else {
            Ok(StateStatement::State(Box::new(node)))
        }
    }

    fn parse_aliased_state(
        &self,
        start: usize,
        end: usize,
    ) -> Result<(Spanned<String>, Option<Label>, StateNodeKind), ParseError> {
        let close_quote = self.source[start + 1..end]
            .find('"')
            .map(|offset| start + 1 + offset)
            .ok_or(ParseError {
                kind: ParseErrorKind::ExpectedStateId,
                span: Span::new(start, end),
            })?;
        let label = label_from_body(self.source, start, close_quote + 1);
        let after_label = close_quote + 1;
        let Some(as_offset) = self.source[after_label..end].find(" as ") else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedStateId,
                span: Span::new(after_label, end),
            });
        };
        let id_start = after_label + as_offset + 4;
        let id =
            parse_single_identifier(self.source, id_start, end, ParseErrorKind::ExpectedStateId)?;
        Ok((id, Some(label), StateNodeKind::Default))
    }

    fn parse_named_state(
        &self,
        start: usize,
        end: usize,
    ) -> Result<(Spanned<String>, Option<Label>, StateNodeKind), ParseError> {
        let Some((trim_start, trim_end)) = trim_ascii_range(&self.source[start..end]) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedStateId,
                span: Span::new(start, end),
            });
        };
        let absolute_start = start + trim_start;
        let absolute_end = start + trim_end;
        let rest = &self.source[absolute_start..absolute_end];
        let id_end = rest
            .find(|value: char| value.is_ascii_whitespace())
            .map_or(absolute_end, |offset| absolute_start + offset);
        let id = parse_state_endpoint(
            self.source,
            absolute_start,
            id_end,
            ParseErrorKind::ExpectedStateId,
        )?;
        let tag = trim_ascii_range(&self.source[id_end..absolute_end])
            .map(|(tag_start, tag_end)| &self.source[id_end + tag_start..id_end + tag_end]);
        let kind = match tag {
            Some("<<choice>>") => StateNodeKind::Choice,
            Some("<<fork>>") => StateNodeKind::Fork,
            Some("<<join>>") => StateNodeKind::Join,
            Some("<<end>>") => StateNodeKind::End,
            _ if id.value == "[*]" => StateNodeKind::Start,
            _ => StateNodeKind::Default,
        };
        Ok((id, None, kind))
    }
}

struct ClassHeaderParser<'source> {
    source: &'source str,
}

impl<'source> ClassHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<ClassHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedClassHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "classDiagram" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedClassHeader,
                span: Span::new(start, end),
            });
        }
        Ok(ClassHeader {
            span: Span::new(start, end),
        })
    }
}

struct ClassStatementParser<'source> {
    source: &'source str,
}

#[derive(Debug, Clone, Copy)]
struct ClassRelationshipOperator {
    token: &'static str,
    line: ClassRelationshipLine,
    start_marker: ClassRelationshipMarker,
    end_marker: ClassRelationshipMarker,
}

impl<'source> ClassStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<ClassStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownClassStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(ClassStatement::Directive(shift_directive(directive, start)));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(ClassStatement::Comment(shift_comment(comment, start)));
        }
        if let Some(direction) = parse_direction_statement(trimmed, start)? {
            return Ok(ClassStatement::Direction(direction));
        }
        if let Some(relationship) = self.parse_relationship(start, end)? {
            return Ok(ClassStatement::Relationship(Box::new(relationship)));
        }
        if let Some(member) = self.parse_inline_member(start, end)? {
            return Ok(ClassStatement::Member(Box::new(member)));
        }
        if has_keyword(self.source, start, "class") {
            let end = if self.source.as_bytes().get(end.saturating_sub(1)) == Some(&b'{') {
                end - 1
            } else {
                end
            };
            return Ok(ClassStatement::Class(Box::new(parse_class_declaration(
                self.source,
                start,
                end,
                ParseErrorKind::ExpectedClassName,
            )?)));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownClassStatement,
            span: Span::new(start, end),
        })
    }

    fn parse_inline_member(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<ClassMemberAssignment>, ParseError> {
        let Some(colon) = self.source[start..end].find(':') else {
            return Ok(None);
        };
        let colon = start + colon;
        let class_id =
            parse_single_identifier(self.source, start, colon, ParseErrorKind::ExpectedClassName)?;
        let member = parse_class_member(self.source, colon + 1, end)?;
        Ok(Some(ClassMemberAssignment {
            class_id,
            member,
            span: Span::new(start, end),
        }))
    }

    fn parse_relationship(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<ClassRelationship>, ParseError> {
        let Some((operator_start, operator)) =
            find_class_relationship_operator(self.source, start, end)
        else {
            return Ok(None);
        };
        let operator_end = operator_start + operator.token.len();
        let from = parse_single_identifier(
            self.source,
            start,
            operator_start,
            ParseErrorKind::ExpectedClassRelationship,
        )?;
        let label_start = self.source[operator_end..end]
            .find(':')
            .map(|offset| operator_end + offset);
        let to_end = label_start.unwrap_or(end);
        let to = parse_single_identifier(
            self.source,
            operator_end,
            to_end,
            ParseErrorKind::ExpectedClassRelationship,
        )?;
        let label = label_start.and_then(|offset| label_from_trimmed(self.source, offset + 1, end));
        Ok(Some(ClassRelationship {
            from,
            to,
            line: operator.line,
            start_marker: operator.start_marker,
            end_marker: operator.end_marker,
            label,
            span: Span::new(start, end),
        }))
    }
}

struct ErHeaderParser<'source> {
    source: &'source str,
}

impl<'source> ErHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<ErHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedErHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "erDiagram" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedErHeader,
                span: Span::new(start, end),
            });
        }
        Ok(ErHeader {
            span: Span::new(start, end),
        })
    }
}

struct ErStatementParser<'source> {
    source: &'source str,
}

#[derive(Debug, Clone)]
struct ErRelationshipOperator {
    token: String,
    start_cardinality: ErCardinality,
    end_cardinality: ErCardinality,
    identifying: bool,
}

impl<'source> ErStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<ErStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownErStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(ErStatement::Directive(shift_directive(directive, start)));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(ErStatement::Comment(shift_comment(comment, start)));
        }
        if let Some(relationship) = self.parse_relationship(start, end)? {
            return Ok(ErStatement::Relationship(Box::new(relationship)));
        }
        if is_er_block_header(trimmed) || is_identifier(trimmed) {
            let end = if self.source.as_bytes().get(end.saturating_sub(1)) == Some(&b'{') {
                end - 1
            } else {
                end
            };
            return Ok(ErStatement::Entity(Box::new(parse_er_entity_header(
                self.source,
                start,
                end,
            )?)));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownErStatement,
            span: Span::new(start, end),
        })
    }

    fn parse_relationship(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<ErRelationship>, ParseError> {
        let Some((operator_start, operator)) =
            find_er_relationship_operator(self.source, start, end)
        else {
            return Ok(None);
        };
        let operator_end = operator_start + operator.token.len();
        let from = parse_single_identifier(
            self.source,
            start,
            operator_start,
            ParseErrorKind::ExpectedErRelationship,
        )?;
        let label_start = self.source[operator_end..end]
            .find(':')
            .map(|offset| operator_end + offset);
        let to_end = label_start.unwrap_or(end);
        let to = parse_single_identifier(
            self.source,
            operator_end,
            to_end,
            ParseErrorKind::ExpectedErRelationship,
        )?;
        let label = label_start.and_then(|offset| label_from_trimmed(self.source, offset + 1, end));
        Ok(Some(ErRelationship {
            from,
            to,
            start_cardinality: operator.start_cardinality,
            end_cardinality: operator.end_cardinality,
            identifying: operator.identifying,
            label,
            span: Span::new(start, end),
        }))
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
            if let Ok(edges) = parse_flow_edge_chain(trimmed)
                && edges.len() > 1
                && edges.iter().all(|edge| {
                    edge.link.value.arrow_start != ArrowHead::None
                        || edge.link.value.arrow_end != ArrowHead::None
                })
            {
                subgraph.statements.extend(
                    edges.into_iter().map(|edge| {
                        FlowStatement::Edge(Box::new(shift_edge(edge, absolute_start)))
                    }),
                );
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

fn source_line(source: &str, cursor: usize) -> Option<SourceLine<'_>> {
    if cursor >= source.len() {
        return None;
    }
    let rest = &source[cursor..];
    let relative_end = rest.find(['\n', '\r']).unwrap_or(rest.len());
    let end = cursor + relative_end;
    let next = if end == source.len() {
        end
    } else if source[end..].starts_with("\r\n") {
        end + 2
    } else {
        end + 1
    };
    Some(SourceLine {
        start: cursor,
        text: &source[cursor..end],
        next,
    })
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

fn parse_single_identifier(
    source: &str,
    start: usize,
    end: usize,
    error_kind: ParseErrorKind,
) -> Result<Spanned<String>, ParseError> {
    let mut values = Vec::new();
    push_identifier(source, start, end, error_kind, &mut values)?;
    let Some(value) = values.pop() else {
        return Err(ParseError {
            kind: error_kind,
            span: Span::new(start, end),
        });
    };
    Ok(value)
}

fn parse_state_endpoint(
    source: &str,
    start: usize,
    end: usize,
    error_kind: ParseErrorKind,
) -> Result<Spanned<String>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: error_kind,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    if &source[absolute_start..absolute_end] == "[*]" {
        return Ok(Spanned::new(
            "[*]".to_owned(),
            Span::new(absolute_start, absolute_end),
        ));
    }
    parse_single_identifier(source, absolute_start, absolute_end, error_kind)
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

fn find_sequence_arrow(
    source: &str,
    start: usize,
    end: usize,
) -> Option<(usize, SequenceArrow, usize)> {
    let arrows = [
        ("<<-->>", SequenceArrow::DottedBidirectional),
        ("<<->>", SequenceArrow::SolidBidirectional),
        ("-->>", SequenceArrow::DottedArrow),
        ("->>", SequenceArrow::SolidArrow),
        ("--x", SequenceArrow::DottedCross),
        ("-x", SequenceArrow::SolidCross),
        ("--)", SequenceArrow::DottedOpen),
        ("-)", SequenceArrow::SolidOpen),
        ("-->", SequenceArrow::DottedLine),
        ("->", SequenceArrow::SolidLine),
    ];
    let haystack = &source[start..end];
    arrows
        .iter()
        .filter_map(|(needle, arrow)| {
            haystack
                .find(needle)
                .map(|offset| (start + offset, *arrow, needle.len()))
        })
        .min_by_key(|(offset, _, _)| *offset)
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

fn is_class_block_header(source: &str) -> bool {
    let Some((start, end)) = trim_ascii_range(source) else {
        return false;
    };
    source[start..end].ends_with('{') && has_keyword(source, start, "class")
}

fn parse_class_declaration(
    source: &str,
    start: usize,
    end: usize,
    error_kind: ParseErrorKind,
) -> Result<ClassNode, ParseError> {
    let keyword = "class";
    if !has_keyword(source, start, keyword) {
        return Err(ParseError {
            kind: error_kind,
            span: Span::new(start, end),
        });
    }
    let rest_start = start + keyword.len();
    let Some((rest_trim_start, rest_trim_end)) = trim_ascii_range(&source[rest_start..end]) else {
        return Err(ParseError {
            kind: error_kind,
            span: Span::new(rest_start, end),
        });
    };
    let absolute_start = rest_start + rest_trim_start;
    let absolute_end = rest_start + rest_trim_end;
    let id_end = source[absolute_start..absolute_end]
        .find(|value: char| value.is_ascii_whitespace())
        .map_or(absolute_end, |offset| absolute_start + offset);
    let id = parse_single_identifier(source, absolute_start, id_end, error_kind)?;
    let mut annotations = Vec::new();
    if id_end < absolute_end {
        let Some((trim_start, trim_end)) = trim_ascii_range(&source[id_end..absolute_end]) else {
            return Ok(ClassNode {
                id,
                annotations,
                members: Vec::new(),
                span: Span::new(start, end),
            });
        };
        let annotation_start = id_end + trim_start;
        let annotation_end = id_end + trim_end;
        if let Some(annotation) = parse_class_annotation(source, annotation_start, annotation_end) {
            annotations.push(annotation);
        } else {
            return Err(ParseError {
                kind: error_kind,
                span: Span::new(annotation_start, annotation_end),
            });
        }
    }
    Ok(ClassNode {
        id,
        annotations,
        members: Vec::new(),
        span: Span::new(start, end),
    })
}

fn parse_class_annotation(source: &str, start: usize, end: usize) -> Option<Label> {
    let (trim_start, trim_end) = trim_ascii_range(&source[start..end])?;
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let value = &source[absolute_start..absolute_end];
    (value.starts_with("<<") && value.ends_with(">>"))
        .then(|| label_from_body(source, absolute_start, absolute_end))
}

fn parse_class_member(source: &str, start: usize, end: usize) -> Result<ClassMember, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedClassMember,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let mut body_start = absolute_start;
    let visibility = source
        .as_bytes()
        .get(body_start)
        .copied()
        .and_then(|value| match value {
            b'+' | b'-' | b'#' | b'~' => {
                body_start += 1;
                Some(value as char)
            }
            _ => None,
        });
    let body = &source[body_start..absolute_end];
    let kind = if body.contains('(') {
        ClassMemberKind::Method
    } else {
        ClassMemberKind::Field
    };
    let (name, ty) = match kind {
        ClassMemberKind::Method => parse_class_method_parts(source, body_start, absolute_end)?,
        ClassMemberKind::Field => parse_class_field_parts(source, body_start, absolute_end)?,
    };
    Ok(ClassMember {
        visibility,
        name,
        ty,
        kind,
        span: Span::new(absolute_start, absolute_end),
    })
}

fn parse_class_method_parts(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(Spanned<String>, Option<Label>), ParseError> {
    let Some(open) = source[start..end].find('(') else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedClassMember,
            span: Span::new(start, end),
        });
    };
    let name = parse_single_identifier(
        source,
        start,
        start + open,
        ParseErrorKind::ExpectedClassMember,
    )?;
    let close = source[start + open..end]
        .find(')')
        .map(|offset| start + open + offset)
        .ok_or(ParseError {
            kind: ParseErrorKind::ExpectedClassMember,
            span: Span::new(start + open, end),
        })?;
    let ty = label_from_trimmed(source, close + 1, end);
    Ok((name, ty))
}

fn parse_class_field_parts(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(Spanned<String>, Option<Label>), ParseError> {
    if let Some(colon) = source[start..end].find(':') {
        let colon = start + colon;
        let name =
            parse_single_identifier(source, start, colon, ParseErrorKind::ExpectedClassMember)?;
        let ty = label_from_trimmed(source, colon + 1, end);
        return Ok((name, ty));
    }
    let parts = source[start..end]
        .split_ascii_whitespace()
        .collect::<Vec<_>>();
    match parts.as_slice() {
        [] => Err(ParseError {
            kind: ParseErrorKind::ExpectedClassMember,
            span: Span::new(start, end),
        }),
        [name] => {
            let name_start = source[start..end]
                .find(name)
                .map_or(start, |offset| start + offset);
            let name = parse_single_identifier(
                source,
                name_start,
                name_start + name.len(),
                ParseErrorKind::ExpectedClassMember,
            )?;
            Ok((name, None))
        }
        [ty, name, ..] => {
            let ty_start = source[start..end]
                .find(ty)
                .map_or(start, |offset| start + offset);
            let name_start = source[ty_start + ty.len()..end]
                .find(name)
                .map_or(ty_start + ty.len(), |offset| ty_start + ty.len() + offset);
            let name = parse_single_identifier(
                source,
                name_start,
                name_start + name.len(),
                ParseErrorKind::ExpectedClassMember,
            )?;
            let ty = label_from_body(source, ty_start, ty_start + ty.len());
            Ok((name, Some(ty)))
        }
    }
}

fn find_class_relationship_operator(
    source: &str,
    start: usize,
    end: usize,
) -> Option<(usize, ClassRelationshipOperator)> {
    class_relationship_operators()
        .into_iter()
        .filter_map(|operator| {
            source[start..end]
                .find(operator.token)
                .map(|offset| (start + offset, operator))
        })
        .min_by_key(|(offset, operator)| (*offset, std::cmp::Reverse(operator.token.len())))
}

fn class_relationship_operators() -> [ClassRelationshipOperator; 14] {
    use ClassRelationshipLine::{Dotted, Solid};
    use ClassRelationshipMarker::{Aggregation, Arrow, Composition, Inheritance, None};
    [
        ClassRelationshipOperator {
            token: "<|--",
            line: Solid,
            start_marker: Inheritance,
            end_marker: None,
        },
        ClassRelationshipOperator {
            token: "--|>",
            line: Solid,
            start_marker: None,
            end_marker: Inheritance,
        },
        ClassRelationshipOperator {
            token: "<|..",
            line: Dotted,
            start_marker: Inheritance,
            end_marker: None,
        },
        ClassRelationshipOperator {
            token: "..|>",
            line: Dotted,
            start_marker: None,
            end_marker: Inheritance,
        },
        ClassRelationshipOperator {
            token: "*--",
            line: Solid,
            start_marker: Composition,
            end_marker: None,
        },
        ClassRelationshipOperator {
            token: "--*",
            line: Solid,
            start_marker: None,
            end_marker: Composition,
        },
        ClassRelationshipOperator {
            token: "o--",
            line: Solid,
            start_marker: Aggregation,
            end_marker: None,
        },
        ClassRelationshipOperator {
            token: "--o",
            line: Solid,
            start_marker: None,
            end_marker: Aggregation,
        },
        ClassRelationshipOperator {
            token: "<--",
            line: Solid,
            start_marker: Arrow,
            end_marker: None,
        },
        ClassRelationshipOperator {
            token: "-->",
            line: Solid,
            start_marker: None,
            end_marker: Arrow,
        },
        ClassRelationshipOperator {
            token: "<..",
            line: Dotted,
            start_marker: Arrow,
            end_marker: None,
        },
        ClassRelationshipOperator {
            token: "..>",
            line: Dotted,
            start_marker: None,
            end_marker: Arrow,
        },
        ClassRelationshipOperator {
            token: "--",
            line: Solid,
            start_marker: None,
            end_marker: None,
        },
        ClassRelationshipOperator {
            token: "..",
            line: Dotted,
            start_marker: None,
            end_marker: None,
        },
    ]
}

fn is_er_block_header(source: &str) -> bool {
    let Some((start, end)) = trim_ascii_range(source) else {
        return false;
    };
    source[start..end].ends_with('{')
        && parse_single_identifier(
            source,
            start,
            end.saturating_sub(1),
            ParseErrorKind::ExpectedErEntity,
        )
        .is_ok()
}

fn parse_er_entity_header(source: &str, start: usize, end: usize) -> Result<ErEntity, ParseError> {
    let id = parse_single_identifier(source, start, end, ParseErrorKind::ExpectedErEntity)?;
    Ok(ErEntity {
        id,
        attributes: Vec::new(),
        span: Span::new(start, end),
    })
}

fn parse_er_attribute(source: &str, start: usize, end: usize) -> Result<ErAttribute, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedErAttribute,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let parts = source[absolute_start..absolute_end]
        .split_ascii_whitespace()
        .collect::<Vec<_>>();
    let [ty, name, rest @ ..] = parts.as_slice() else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedErAttribute,
            span: Span::new(absolute_start, absolute_end),
        });
    };
    let ty_start = source[absolute_start..absolute_end]
        .find(ty)
        .map_or(absolute_start, |offset| absolute_start + offset);
    let name_start = source[ty_start + ty.len()..absolute_end]
        .find(name)
        .map_or(ty_start + ty.len(), |offset| ty_start + ty.len() + offset);
    let key = rest.first().and_then(|key| {
        let key_start = source[name_start + name.len()..absolute_end]
            .find(key)
            .map(|offset| name_start + name.len() + offset)?;
        Some(Spanned::new(
            (*key).to_owned(),
            Span::new(key_start, key_start + key.len()),
        ))
    });
    Ok(ErAttribute {
        ty: Spanned::new((*ty).to_owned(), Span::new(ty_start, ty_start + ty.len())),
        name: Spanned::new(
            (*name).to_owned(),
            Span::new(name_start, name_start + name.len()),
        ),
        key,
        span: Span::new(absolute_start, absolute_end),
    })
}

fn find_er_relationship_operator(
    source: &str,
    start: usize,
    end: usize,
) -> Option<(usize, ErRelationshipOperator)> {
    er_relationship_operators()
        .into_iter()
        .filter_map(|operator| {
            source[start..end]
                .find(&operator.token)
                .map(|offset| (start + offset, operator))
        })
        .min_by_key(|(offset, operator)| (*offset, std::cmp::Reverse(operator.token.len())))
}

fn er_relationship_operators() -> Vec<ErRelationshipOperator> {
    let ends = [
        ("||", ErCardinality::One),
        ("|o", ErCardinality::ZeroOrOne),
        ("o|", ErCardinality::ZeroOrOne),
        ("}|", ErCardinality::OneOrMany),
        ("|{", ErCardinality::OneOrMany),
        ("}o", ErCardinality::ZeroOrMany),
        ("o{", ErCardinality::ZeroOrMany),
    ];
    let mut operators = Vec::new();
    for (left, start_cardinality) in ends {
        for (right, end_cardinality) in ends {
            operators.push(ErRelationshipOperator {
                token: format!("{left}--{right}"),
                start_cardinality,
                end_cardinality,
                identifying: true,
            });
            operators.push(ErRelationshipOperator {
                token: format!("{left}..{right}"),
                start_cardinality,
                end_cardinality,
                identifying: false,
            });
        }
    }
    operators
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

fn shift_flowchart_header(header: FlowchartHeader, offset: usize) -> FlowchartHeader {
    FlowchartHeader {
        directive: shift_spanned(header.directive, offset),
        direction: shift_spanned(header.direction, offset),
        span: shift_span(header.span, offset),
    }
}

fn shift_subgraph(subgraph: FlowSubgraph, offset: usize) -> FlowSubgraph {
    FlowSubgraph {
        id: shift_spanned(subgraph.id, offset),
        label: subgraph.label.map(|label| shift_label(label, offset)),
        direction: subgraph
            .direction
            .map(|direction| shift_spanned(direction, offset)),
        statements: subgraph
            .statements
            .into_iter()
            .map(|statement| shift_flow_statement(statement, offset))
            .collect(),
        span: shift_span(subgraph.span, offset),
    }
}

fn shift_flow_statement(statement: FlowStatement, offset: usize) -> FlowStatement {
    match statement {
        FlowStatement::Node(node) => FlowStatement::Node(shift_node(node, offset)),
        FlowStatement::Edge(edge) => FlowStatement::Edge(Box::new(shift_edge(*edge, offset))),
        FlowStatement::Subgraph(subgraph) => {
            FlowStatement::Subgraph(shift_subgraph(subgraph, offset))
        }
        FlowStatement::ClassDef(class_def) => {
            FlowStatement::ClassDef(shift_class_def(class_def, offset))
        }
        FlowStatement::ClassApply(class_apply) => {
            FlowStatement::ClassApply(shift_class_apply(class_apply, offset))
        }
        FlowStatement::Comment(comment) => FlowStatement::Comment(shift_comment(comment, offset)),
        FlowStatement::Directive(directive) => {
            FlowStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_sequence_header(header: SequenceHeader, offset: usize) -> SequenceHeader {
    SequenceHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_sequence_statement(statement: SequenceStatement, offset: usize) -> SequenceStatement {
    match statement {
        SequenceStatement::Participant(participant) => SequenceStatement::Participant(Box::new(
            shift_sequence_participant(*participant, offset),
        )),
        SequenceStatement::Message(message) => {
            SequenceStatement::Message(Box::new(shift_sequence_message(*message, offset)))
        }
        SequenceStatement::ActivationStart(participant) => {
            SequenceStatement::ActivationStart(shift_spanned(participant, offset))
        }
        SequenceStatement::ActivationEnd(participant) => {
            SequenceStatement::ActivationEnd(shift_spanned(participant, offset))
        }
        SequenceStatement::Note(note) => {
            SequenceStatement::Note(Box::new(shift_sequence_note(*note, offset)))
        }
        SequenceStatement::Control(control) => {
            SequenceStatement::Control(Box::new(shift_sequence_control(*control, offset)))
        }
        SequenceStatement::AutoNumber(auto_number) => {
            SequenceStatement::AutoNumber(shift_sequence_auto_number(auto_number, offset))
        }
        SequenceStatement::Comment(comment) => {
            SequenceStatement::Comment(shift_comment(comment, offset))
        }
        SequenceStatement::Directive(directive) => {
            SequenceStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_sequence_participant(
    participant: SequenceParticipant,
    offset: usize,
) -> SequenceParticipant {
    SequenceParticipant {
        id: shift_spanned(participant.id, offset),
        alias: participant.alias.map(|label| shift_label(label, offset)),
        kind: participant.kind,
        span: shift_span(participant.span, offset),
    }
}

fn shift_sequence_message(message: SequenceMessage, offset: usize) -> SequenceMessage {
    SequenceMessage {
        from: shift_spanned(message.from, offset),
        to: shift_spanned(message.to, offset),
        arrow: message.arrow,
        label: message.label.map(|label| shift_label(label, offset)),
        span: shift_span(message.span, offset),
    }
}

fn shift_sequence_note(note: SequenceNote, offset: usize) -> SequenceNote {
    SequenceNote {
        placement: note.placement,
        participants: note
            .participants
            .into_iter()
            .map(|participant| shift_spanned(participant, offset))
            .collect(),
        label: shift_label(note.label, offset),
        span: shift_span(note.span, offset),
    }
}

fn shift_sequence_control(control: SequenceControlBlock, offset: usize) -> SequenceControlBlock {
    SequenceControlBlock {
        kind: control.kind,
        label: control.label.map(|label| shift_label(label, offset)),
        statements: control
            .statements
            .into_iter()
            .map(|statement| shift_sequence_statement(statement, offset))
            .collect(),
        span: shift_span(control.span, offset),
    }
}

fn shift_sequence_auto_number(
    auto_number: SequenceAutoNumber,
    offset: usize,
) -> SequenceAutoNumber {
    SequenceAutoNumber {
        start: auto_number.start,
        step: auto_number.step,
        span: shift_span(auto_number.span, offset),
    }
}

fn shift_state_header(header: StateHeader, offset: usize) -> StateHeader {
    StateHeader {
        directive: header.directive,
        span: shift_span(header.span, offset),
    }
}

fn shift_state_statement(statement: StateStatement, offset: usize) -> StateStatement {
    match statement {
        StateStatement::State(state) => {
            StateStatement::State(Box::new(shift_state_node(*state, offset)))
        }
        StateStatement::Transition(transition) => {
            StateStatement::Transition(Box::new(shift_state_transition(*transition, offset)))
        }
        StateStatement::Composite(state) => {
            StateStatement::Composite(Box::new(shift_state_node(*state, offset)))
        }
        StateStatement::ClassDef(class_def) => {
            StateStatement::ClassDef(shift_class_def(class_def, offset))
        }
        StateStatement::ClassApply(class_apply) => {
            StateStatement::ClassApply(shift_state_class_apply(class_apply, offset))
        }
        StateStatement::Direction(direction) => {
            StateStatement::Direction(shift_spanned(direction, offset))
        }
        StateStatement::Comment(comment) => StateStatement::Comment(shift_comment(comment, offset)),
        StateStatement::Directive(directive) => {
            StateStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_state_node(state: StateNode, offset: usize) -> StateNode {
    StateNode {
        id: shift_spanned(state.id, offset),
        label: state.label.map(|label| shift_label(label, offset)),
        kind: state.kind,
        descriptions: state
            .descriptions
            .into_iter()
            .map(|label| shift_label(label, offset))
            .collect(),
        note: state.note.map(|note| shift_state_note(note, offset)),
        children: state
            .children
            .into_iter()
            .map(|statement| shift_state_statement(statement, offset))
            .collect(),
        span: shift_span(state.span, offset),
    }
}

fn shift_state_transition(transition: StateTransition, offset: usize) -> StateTransition {
    StateTransition {
        from: shift_spanned(transition.from, offset),
        to: shift_spanned(transition.to, offset),
        label: transition.label.map(|label| shift_label(label, offset)),
        span: shift_span(transition.span, offset),
    }
}

fn shift_state_note(note: StateNote, offset: usize) -> StateNote {
    StateNote {
        placement: note.placement,
        label: shift_label(note.label, offset),
        span: shift_span(note.span, offset),
    }
}

fn shift_state_class_apply(class_apply: StateClassApply, offset: usize) -> StateClassApply {
    StateClassApply {
        state_ids: class_apply
            .state_ids
            .into_iter()
            .map(|state_id| shift_spanned(state_id, offset))
            .collect(),
        class_ids: class_apply
            .class_ids
            .into_iter()
            .map(|class_id| shift_spanned(class_id, offset))
            .collect(),
        span: shift_span(class_apply.span, offset),
    }
}

fn shift_class_header(header: ClassHeader, offset: usize) -> ClassHeader {
    ClassHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_class_statement(statement: ClassStatement, offset: usize) -> ClassStatement {
    match statement {
        ClassStatement::Class(class) => {
            ClassStatement::Class(Box::new(shift_class_node(*class, offset)))
        }
        ClassStatement::Member(member) => {
            ClassStatement::Member(Box::new(shift_class_member_assignment(*member, offset)))
        }
        ClassStatement::Relationship(relationship) => {
            ClassStatement::Relationship(Box::new(shift_class_relationship(*relationship, offset)))
        }
        ClassStatement::Direction(direction) => {
            ClassStatement::Direction(shift_spanned(direction, offset))
        }
        ClassStatement::Comment(comment) => ClassStatement::Comment(shift_comment(comment, offset)),
        ClassStatement::Directive(directive) => {
            ClassStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_class_node(class: ClassNode, offset: usize) -> ClassNode {
    ClassNode {
        id: shift_spanned(class.id, offset),
        annotations: class
            .annotations
            .into_iter()
            .map(|annotation| shift_label(annotation, offset))
            .collect(),
        members: class
            .members
            .into_iter()
            .map(|member| shift_class_member(member, offset))
            .collect(),
        span: shift_span(class.span, offset),
    }
}

fn shift_class_member_assignment(
    member: ClassMemberAssignment,
    offset: usize,
) -> ClassMemberAssignment {
    ClassMemberAssignment {
        class_id: shift_spanned(member.class_id, offset),
        member: shift_class_member(member.member, offset),
        span: shift_span(member.span, offset),
    }
}

fn shift_class_member(member: ClassMember, offset: usize) -> ClassMember {
    ClassMember {
        visibility: member.visibility,
        name: shift_spanned(member.name, offset),
        ty: member.ty.map(|label| shift_label(label, offset)),
        kind: member.kind,
        span: shift_span(member.span, offset),
    }
}

fn shift_class_relationship(relationship: ClassRelationship, offset: usize) -> ClassRelationship {
    ClassRelationship {
        from: shift_spanned(relationship.from, offset),
        to: shift_spanned(relationship.to, offset),
        line: relationship.line,
        start_marker: relationship.start_marker,
        end_marker: relationship.end_marker,
        label: relationship.label.map(|label| shift_label(label, offset)),
        span: shift_span(relationship.span, offset),
    }
}

fn shift_er_header(header: ErHeader, offset: usize) -> ErHeader {
    ErHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_er_statement(statement: ErStatement, offset: usize) -> ErStatement {
    match statement {
        ErStatement::Entity(entity) => {
            ErStatement::Entity(Box::new(shift_er_entity(*entity, offset)))
        }
        ErStatement::Relationship(relationship) => {
            ErStatement::Relationship(Box::new(shift_er_relationship(*relationship, offset)))
        }
        ErStatement::Comment(comment) => ErStatement::Comment(shift_comment(comment, offset)),
        ErStatement::Directive(directive) => {
            ErStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_er_entity(entity: ErEntity, offset: usize) -> ErEntity {
    ErEntity {
        id: shift_spanned(entity.id, offset),
        attributes: entity
            .attributes
            .into_iter()
            .map(|attribute| shift_er_attribute(attribute, offset))
            .collect(),
        span: shift_span(entity.span, offset),
    }
}

fn shift_er_attribute(attribute: ErAttribute, offset: usize) -> ErAttribute {
    ErAttribute {
        ty: shift_spanned(attribute.ty, offset),
        name: shift_spanned(attribute.name, offset),
        key: attribute.key.map(|key| shift_spanned(key, offset)),
        span: shift_span(attribute.span, offset),
    }
}

fn shift_er_relationship(relationship: ErRelationship, offset: usize) -> ErRelationship {
    ErRelationship {
        from: shift_spanned(relationship.from, offset),
        to: shift_spanned(relationship.to, offset),
        start_cardinality: relationship.start_cardinality,
        end_cardinality: relationship.end_cardinality,
        identifying: relationship.identifying,
        label: relationship.label.map(|label| shift_label(label, offset)),
        span: shift_span(relationship.span, offset),
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
        ArrowHead, ClassMemberKind, ClassRelationshipLine, ClassRelationshipMarker, ClassStatement,
        DiagramKind, Direction, ErCardinality, ErStatement, FlowEdgeStroke, FlowShape,
        FlowStatement, FlowchartDirective, LabelKind, SequenceArrow, SequenceControlKind,
        SequenceNotePlacement, SequenceParticipantKind, SequenceStatement, Span, StateDirective,
        StateNodeKind, StateStatement,
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
    fn parses_flowchart_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "%%{ init: {} }%%\ngraph TD\nA --> B\nsubgraph group\nC --> D\nend",
        )
        .unwrap();

        assert_eq!(diagram.directives.len(), 1);
        let DiagramKind::Flowchart(ast) = diagram.kind else {
            panic!("expected flowchart diagram");
        };
        assert_eq!(ast.header.direction.value, Direction::TopDown);
        assert_eq!(ast.edges.len(), 1);
        assert_eq!(ast.subgraphs.len(), 1);
        assert!(matches!(ast.statements[1], FlowStatement::Subgraph(_)));
    }

    #[test]
    fn parses_single_line_flow_edge_chains() {
        let ast = Parser::parse_flowchart("graph LR\nA --> B --> C").unwrap();

        assert_eq!(ast.edges.len(), 2);
        assert_eq!(ast.edges[0].from.id.value, "A");
        assert_eq!(ast.edges[0].to.id.value, "B");
        assert_eq!(ast.edges[1].from.id.value, "B");
        assert_eq!(ast.edges[1].to.id.value, "C");
    }

    #[test]
    fn parses_sequence_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "sequenceDiagram\nparticipant Alice as Alice Doe\nAlice->>Bob: hello",
        )
        .unwrap();

        let DiagramKind::Sequence(ast) = diagram.kind else {
            panic!("expected sequence diagram");
        };
        assert_eq!(ast.participants.len(), 1);
        assert_eq!(ast.statements.len(), 2);
    }

    #[test]
    fn parses_state_document_to_diagram() {
        let diagram = Parser::parse_diagram("stateDiagram-v2\ndirection LR\n[*] --> Idle").unwrap();

        let DiagramKind::State(ast) = diagram.kind else {
            panic!("expected state diagram");
        };
        assert_eq!(ast.direction.unwrap().value, Direction::LeftRight);
        assert_eq!(ast.transitions.len(), 1);
    }

    #[test]
    fn parses_class_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "classDiagram\nclass Animal {\n+String name\n+eat() void\n}\nAnimal <|-- Dog",
        )
        .unwrap();

        let DiagramKind::Class(ast) = diagram.kind else {
            panic!("expected class diagram");
        };
        assert_eq!(ast.classes.len(), 2);
        assert_eq!(ast.classes[0].id.value, "Animal");
        assert_eq!(ast.classes[0].members.len(), 2);
        assert_eq!(ast.relationships.len(), 1);
        assert_eq!(
            ast.relationships[0].start_marker,
            ClassRelationshipMarker::Inheritance,
        );
    }

    #[test]
    fn parses_er_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "erDiagram\nCUSTOMER {\nstring name PK\n}\nCUSTOMER ||--o{ ORDER : places",
        )
        .unwrap();

        let DiagramKind::Er(ast) = diagram.kind else {
            panic!("expected ER diagram");
        };
        assert_eq!(ast.entities.len(), 2);
        assert_eq!(ast.entities[0].attributes.len(), 1);
        assert_eq!(ast.relationships.len(), 1);
        assert_eq!(
            ast.relationships[0].end_cardinality,
            ErCardinality::ZeroOrMany,
        );
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

    #[test]
    fn parses_sequence_header() {
        assert_eq!(
            Parser::parse_sequence_header(" sequenceDiagram ")
                .unwrap()
                .span,
            Span::new(1, 16),
        );
    }

    #[test]
    fn parses_sequence_participants_and_actors() {
        let participant =
            Parser::parse_sequence_statement("participant Alice as Alice Doe").unwrap();
        let actor = Parser::parse_sequence_statement("actor Bob").unwrap();

        let SequenceStatement::Participant(participant) = participant else {
            panic!("expected participant statement");
        };
        let SequenceStatement::Participant(actor) = actor else {
            panic!("expected actor statement");
        };
        assert_eq!(participant.id.value, "Alice");
        assert_eq!(participant.alias.unwrap().text, "Alice Doe");
        assert_eq!(participant.kind, SequenceParticipantKind::Participant);
        assert_eq!(actor.kind, SequenceParticipantKind::Actor);
    }

    #[test]
    fn parses_sequence_messages() {
        let cases = [
            ("Alice->Bob: plain", SequenceArrow::SolidLine),
            ("Alice-->Bob: dotted", SequenceArrow::DottedLine),
            ("Alice->>Bob: arrow", SequenceArrow::SolidArrow),
            ("Alice-->>Bob: dotted arrow", SequenceArrow::DottedArrow),
            ("Alice-xBob: cross", SequenceArrow::SolidCross),
            ("Alice--)Bob: open", SequenceArrow::DottedOpen),
            ("Alice<<->>Bob: both", SequenceArrow::SolidBidirectional),
        ];

        for (source, arrow) in cases {
            let statement = Parser::parse_sequence_statement(source).unwrap();
            let SequenceStatement::Message(message) = statement else {
                panic!("expected message statement");
            };
            assert_eq!(message.from.value, "Alice");
            assert_eq!(message.to.value, "Bob");
            assert_eq!(message.arrow, arrow);
            assert!(message.label.is_some());
        }
    }

    #[test]
    fn parses_sequence_note() {
        let statement =
            Parser::parse_sequence_statement("Note over Alice,Bob: Shared state").unwrap();

        let SequenceStatement::Note(note) = statement else {
            panic!("expected note statement");
        };
        assert_eq!(note.placement, SequenceNotePlacement::Over);
        assert_eq!(note.participants.len(), 2);
        assert_eq!(note.label.text, "Shared state");
    }

    #[test]
    fn parses_sequence_control_starts() {
        let cases = [
            ("loop Retry", SequenceControlKind::Loop),
            ("alt Success", SequenceControlKind::Alt),
            ("opt Cache hit", SequenceControlKind::Opt),
            ("par Worker A", SequenceControlKind::Par),
        ];

        for (source, kind) in cases {
            let statement = Parser::parse_sequence_statement(source).unwrap();
            let SequenceStatement::Control(control) = statement else {
                panic!("expected control statement");
            };
            assert_eq!(control.kind, kind);
            assert!(control.label.is_some());
        }
    }

    #[test]
    fn rejects_unknown_sequence_statement() {
        assert_eq!(
            Parser::parse_sequence_statement("else no branch")
                .unwrap_err()
                .kind,
            ParseErrorKind::UnknownSequenceStatement,
        );
    }

    #[test]
    fn parses_state_headers() {
        assert_eq!(
            Parser::parse_state_header("stateDiagram-v2")
                .unwrap()
                .directive,
            StateDirective::StateDiagramV2,
        );
        assert_eq!(
            Parser::parse_state_header("stateDiagram")
                .unwrap()
                .directive,
            StateDirective::StateDiagram,
        );
    }

    #[test]
    fn parses_state_transitions() {
        let statement = Parser::parse_state_statement("[*] --> Idle: boot").unwrap();

        let StateStatement::Transition(transition) = statement else {
            panic!("expected transition statement");
        };
        assert_eq!(transition.from.value, "[*]");
        assert_eq!(transition.to.value, "Idle");
        assert_eq!(transition.label.unwrap().text, "boot");
    }

    #[test]
    fn parses_state_declarations() {
        let aliased = Parser::parse_state_statement(r#"state "Power On" as power_on"#).unwrap();
        let choice = Parser::parse_state_statement("state decision <<choice>>").unwrap();
        let fork = Parser::parse_state_statement("state split <<fork>>").unwrap();

        let StateStatement::State(aliased) = aliased else {
            panic!("expected aliased state");
        };
        let StateStatement::State(choice) = choice else {
            panic!("expected choice state");
        };
        let StateStatement::State(fork) = fork else {
            panic!("expected fork state");
        };
        assert_eq!(aliased.id.value, "power_on");
        assert_eq!(aliased.label.unwrap().text, "Power On");
        assert_eq!(choice.kind, StateNodeKind::Choice);
        assert_eq!(fork.kind, StateNodeKind::Fork);
    }

    #[test]
    fn parses_composite_state_opening() {
        let statement = Parser::parse_state_statement("state Composite {").unwrap();

        let StateStatement::Composite(state) = statement else {
            panic!("expected composite state");
        };
        assert_eq!(state.id.value, "Composite");
    }

    #[test]
    fn parses_state_direction_comments_and_directives() {
        let direction = Parser::parse_state_statement("direction LR").unwrap();
        let comment = Parser::parse_state_statement("%% state note").unwrap();
        let directive = Parser::parse_state_statement("%%{ init: {} }%%").unwrap();

        assert!(matches!(direction, StateStatement::Direction(_)));
        assert!(matches!(comment, StateStatement::Comment(_)));
        assert!(matches!(directive, StateStatement::Directive(_)));
    }

    #[test]
    fn rejects_unknown_state_statement() {
        assert_eq!(
            Parser::parse_state_statement("elsewhere").unwrap_err().kind,
            ParseErrorKind::UnknownStateStatement,
        );
    }

    #[test]
    fn parses_class_members_and_relationships() {
        let member = Parser::parse_class_statement("Animal : +String name").unwrap();
        let relationship = Parser::parse_class_statement("Client ..> Server : uses").unwrap();

        let ClassStatement::Member(member) = member else {
            panic!("expected member statement");
        };
        let ClassStatement::Relationship(relationship) = relationship else {
            panic!("expected relationship statement");
        };
        assert_eq!(member.class_id.value, "Animal");
        assert_eq!(member.member.visibility, Some('+'));
        assert_eq!(member.member.name.value, "name");
        assert_eq!(member.member.ty.unwrap().text, "String");
        assert_eq!(member.member.kind, ClassMemberKind::Field);
        assert_eq!(relationship.line, ClassRelationshipLine::Dotted);
        assert_eq!(relationship.end_marker, ClassRelationshipMarker::Arrow);
        assert_eq!(relationship.label.unwrap().text, "uses");
    }

    #[test]
    fn parses_er_relationships() {
        let relationship = Parser::parse_er_statement("CUSTOMER ||--o{ ORDER : places").unwrap();

        let ErStatement::Relationship(relationship) = relationship else {
            panic!("expected ER relationship");
        };
        assert_eq!(relationship.from.value, "CUSTOMER");
        assert_eq!(relationship.to.value, "ORDER");
        assert_eq!(relationship.start_cardinality, ErCardinality::One);
        assert_eq!(relationship.end_cardinality, ErCardinality::ZeroOrMany);
        assert!(relationship.identifying);
        assert_eq!(relationship.label.unwrap().text, "places");
    }

    #[test]
    fn rejects_unknown_er_statement() {
        assert_eq!(
            Parser::parse_er_statement("else where").unwrap_err().kind,
            ParseErrorKind::UnknownErStatement,
        );
    }

    #[test]
    fn rejects_unknown_class_statement() {
        assert_eq!(
            Parser::parse_class_statement("elsewhere").unwrap_err().kind,
            ParseErrorKind::UnknownClassStatement,
        );
    }
}
