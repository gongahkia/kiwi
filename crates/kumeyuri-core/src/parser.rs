use crate::ast::{
    ArchitectureAlignAxis, ArchitectureAlignment, ArchitectureAst, ArchitectureEdge,
    ArchitectureEndpoint, ArchitectureGroup, ArchitectureHeader, ArchitectureJunction,
    ArchitectureService, ArchitectureSide, ArchitectureStatement, ArrowHead, BlockArrowDirection,
    BlockContainer, BlockDiagramAst, BlockDiagramHeader, BlockEdge, BlockNode, BlockShape,
    BlockSpace, BlockStatement, BlockStyle, C4Ast, C4Boundary, C4BoundaryKind, C4CallArg,
    C4DiagramType, C4Element, C4ElementKind, C4Header, C4LayoutConfig, C4Relationship,
    C4RelationshipKind, C4Statement, C4StyleUpdate, ClassAst, ClassHeader, ClassMember,
    ClassMemberAssignment, ClassMemberKind, ClassNode, ClassRelationship, ClassRelationshipLine,
    ClassRelationshipMarker, ClassStatement, Diagram, DiagramKind, DiagramMetadata, Direction,
    ErAst, ErAttribute, ErCardinality, ErEntity, ErHeader, ErRelationship, ErStatement,
    EventModelingAst, EventModelingData, EventModelingDataBlock, EventModelingEntityType,
    EventModelingFrameKind, EventModelingHeader, EventModelingStatement, EventModelingTimeFrame,
    FlowClassApply, FlowClassDef, FlowEdge, FlowEdgeLink, FlowEdgeStroke, FlowNode, FlowShape,
    FlowStatement, FlowStyleDeclaration, FlowSubgraph, FlowchartAst, FlowchartDirective,
    FlowchartHeader, GanttAst, GanttConfigStatement, GanttHeader, GanttStatement, GanttTask,
    GanttTaskTag, GitGraphAst, GitGraphBranch, GitGraphCherryPick, GitGraphCommit,
    GitGraphCommitKind, GitGraphHeader, GitGraphMerge, GitGraphOrientation, GitGraphStatement,
    IshikawaAst, IshikawaHeader, IshikawaNode, IshikawaStatement, JourneyAst, JourneyHeader,
    JourneyStatement, JourneyTask, KanbanAst, KanbanColumn, KanbanHeader, KanbanMetadata,
    KanbanStatement, KanbanTask, Label, LabelKind, MermaidComment, MermaidDirective, MindmapAst,
    MindmapHeader, MindmapNode, MindmapShape, MindmapStatement, PacketAst, PacketField,
    PacketHeader, PacketRange, PacketStatement, PieAst, PieConfig, PieHeader, PieLegendPosition,
    PieSlice, PieStatement, QuadrantAst, QuadrantAxis, QuadrantAxisKind, QuadrantHeader,
    QuadrantPoint, QuadrantSection, QuadrantStatement, RadarAst, RadarAxis, RadarCurve,
    RadarCurveValue, RadarHeader, RadarOption, RadarOptionKind, RadarStatement, RequirementAst,
    RequirementElement, RequirementHeader, RequirementKind, RequirementNode,
    RequirementRelationship, RequirementRelationshipKind, RequirementRisk, RequirementStatement,
    RequirementStyle, RequirementVerifyMethod, SankeyAst, SankeyHeader, SankeyLink,
    SankeyStatement, SequenceActivation, SequenceArrow, SequenceAst, SequenceAutoNumber,
    SequenceBox, SequenceControlBlock, SequenceControlKind, SequenceCreate, SequenceDestroy,
    SequenceHeader, SequenceMessage, SequenceNote, SequenceNotePlacement, SequenceParticipant,
    SequenceParticipantKind, SequenceStatement, Span, Spanned, StateAst, StateClassApply,
    StateDirective, StateHeader, StateNode, StateNodeKind, StateNote, StateStatement,
    StateTransition, TimelineAst, TimelineHeader, TimelinePeriod, TimelineStatement, TreemapAst,
    TreemapHeader, TreemapNode, TreemapStatement, VennAst, VennHeader, VennSet, VennStatement,
    VennStyle, VennText, VennTextOwner, VennUnion, WardleyAnnotation, WardleyAst, WardleyComponent,
    WardleyComponentKind, WardleyCoord, WardleyDecorator, WardleyEvolution, WardleyEvolutionStage,
    WardleyEvolve, WardleyForce, WardleyForceKind, WardleyHeader, WardleyLabelOffset, WardleyLink,
    WardleyLinkKind, WardleyNote, WardleySize, WardleyStatement, XyChartAst, XyChartAxis,
    XyChartAxisKind, XyChartAxisScale, XyChartHeader, XyChartOrientation, XyChartSeries,
    XyChartSeriesKind, XyChartStatement, ZenUmlAst, ZenUmlFragment, ZenUmlFragmentKind,
    ZenUmlHeader, ZenUmlMessage, ZenUmlMessageKind, ZenUmlParticipant, ZenUmlStatement,
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
    ReservedFlowNodeLabel,
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
    ExpectedGanttHeader,
    UnknownGanttStatement,
    ExpectedGanttTask,
    ExpectedGanttMetadata,
    ExpectedPieHeader,
    UnknownPieStatement,
    ExpectedPieSlice,
    ExpectedPieValue,
    ExpectedQuadrantHeader,
    UnknownQuadrantStatement,
    ExpectedQuadrantAxis,
    ExpectedQuadrantPoint,
    ExpectedQuadrantValue,
    ExpectedZenUmlHeader,
    UnknownZenUmlStatement,
    ExpectedZenUmlParticipant,
    ExpectedZenUmlMessage,
    ExpectedSankeyHeader,
    UnknownSankeyStatement,
    ExpectedSankeyLink,
    ExpectedSankeyValue,
    ExpectedXyChartHeader,
    UnknownXyChartStatement,
    ExpectedXyChartAxis,
    ExpectedXyChartSeries,
    ExpectedXyChartValue,
    ExpectedBlockHeader,
    UnknownBlockStatement,
    ExpectedBlockNode,
    ExpectedBlockEdge,
    ExpectedPacketHeader,
    UnknownPacketStatement,
    ExpectedPacketField,
    ExpectedPacketRange,
    ExpectedKanbanHeader,
    UnknownKanbanStatement,
    ExpectedKanbanItem,
    ExpectedKanbanMetadata,
    ExpectedArchitectureHeader,
    UnknownArchitectureStatement,
    ExpectedArchitectureNode,
    ExpectedArchitectureEdge,
    ExpectedArchitectureSide,
    ExpectedArchitectureAlignment,
    ExpectedRadarHeader,
    UnknownRadarStatement,
    ExpectedRadarAxis,
    ExpectedRadarCurve,
    ExpectedRadarValue,
    ExpectedRadarOption,
    ExpectedEventModelingHeader,
    UnknownEventModelingStatement,
    ExpectedEventModelingFrame,
    ExpectedEventModelingEntityType,
    ExpectedEventModelingData,
    ExpectedTreemapHeader,
    UnknownTreemapStatement,
    ExpectedTreemapNode,
    ExpectedTreemapValue,
    ExpectedVennHeader,
    UnknownVennStatement,
    ExpectedVennSet,
    ExpectedVennUnion,
    ExpectedVennText,
    ExpectedVennStyle,
    ExpectedVennValue,
    ExpectedIshikawaHeader,
    UnknownIshikawaStatement,
    ExpectedIshikawaEvent,
    ExpectedIshikawaCause,
    ExpectedWardleyHeader,
    UnknownWardleyStatement,
    ExpectedWardleyName,
    ExpectedWardleyCoord,
    ExpectedWardleyValue,
    ExpectedWardleyDecorator,
    ExpectedWardleyLink,
    ExpectedMindmapHeader,
    UnknownMindmapStatement,
    ExpectedMindmapNode,
    ExpectedJourneyHeader,
    UnknownJourneyStatement,
    ExpectedJourneyTask,
    ExpectedJourneyScore,
    ExpectedGitGraphHeader,
    UnknownGitGraphStatement,
    ExpectedGitGraphName,
    ExpectedGitGraphAttribute,
    ExpectedGitGraphCommitKind,
    ExpectedTimelineHeader,
    UnknownTimelineStatement,
    ExpectedTimelinePeriod,
    ExpectedTimelineEvent,
    ExpectedRequirementHeader,
    UnknownRequirementStatement,
    ExpectedRequirementName,
    ExpectedRequirementField,
    ExpectedRequirementRelationship,
    ExpectedRequirementKind,
    ExpectedRequirementRisk,
    ExpectedRequirementVerifyMethod,
    ExpectedC4Header,
    UnknownC4Statement,
    ExpectedC4Call,
    ExpectedC4Argument,
    ExpectedC4Name,
    ExpectedC4Relationship,
    UnsupportedMermaidConfig,
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

    pub fn parse_gantt(source: &str) -> Result<GanttAst, ParseError> {
        DiagramParser::new(source).parse_gantt_only()
    }

    pub fn parse_pie(source: &str) -> Result<PieAst, ParseError> {
        DiagramParser::new(source).parse_pie_only()
    }

    pub fn parse_quadrant(source: &str) -> Result<QuadrantAst, ParseError> {
        DiagramParser::new(source).parse_quadrant_only()
    }

    pub fn parse_zenuml(source: &str) -> Result<ZenUmlAst, ParseError> {
        DiagramParser::new(source).parse_zenuml_only()
    }

    pub fn parse_sankey(source: &str) -> Result<SankeyAst, ParseError> {
        DiagramParser::new(source).parse_sankey_only()
    }

    pub fn parse_xy_chart(source: &str) -> Result<XyChartAst, ParseError> {
        DiagramParser::new(source).parse_xy_chart_only()
    }

    pub fn parse_block_diagram(source: &str) -> Result<BlockDiagramAst, ParseError> {
        DiagramParser::new(source).parse_block_only()
    }

    pub fn parse_packet(source: &str) -> Result<PacketAst, ParseError> {
        DiagramParser::new(source).parse_packet_only()
    }

    pub fn parse_kanban(source: &str) -> Result<KanbanAst, ParseError> {
        DiagramParser::new(source).parse_kanban_only()
    }

    pub fn parse_architecture(source: &str) -> Result<ArchitectureAst, ParseError> {
        DiagramParser::new(source).parse_architecture_only()
    }

    pub fn parse_radar(source: &str) -> Result<RadarAst, ParseError> {
        DiagramParser::new(source).parse_radar_only()
    }

    pub fn parse_event_modeling(source: &str) -> Result<EventModelingAst, ParseError> {
        DiagramParser::new(source).parse_event_modeling_only()
    }

    pub fn parse_treemap(source: &str) -> Result<TreemapAst, ParseError> {
        DiagramParser::new(source).parse_treemap_only()
    }

    pub fn parse_venn(source: &str) -> Result<VennAst, ParseError> {
        DiagramParser::new(source).parse_venn_only()
    }

    pub fn parse_ishikawa(source: &str) -> Result<IshikawaAst, ParseError> {
        DiagramParser::new(source).parse_ishikawa_only()
    }

    pub fn parse_wardley(source: &str) -> Result<WardleyAst, ParseError> {
        DiagramParser::new(source).parse_wardley_only()
    }

    pub fn parse_mindmap(source: &str) -> Result<MindmapAst, ParseError> {
        DiagramParser::new(source).parse_mindmap_only()
    }

    pub fn parse_journey(source: &str) -> Result<JourneyAst, ParseError> {
        DiagramParser::new(source).parse_journey_only()
    }

    pub fn parse_gitgraph(source: &str) -> Result<GitGraphAst, ParseError> {
        DiagramParser::new(source).parse_gitgraph_only()
    }

    pub fn parse_timeline(source: &str) -> Result<TimelineAst, ParseError> {
        DiagramParser::new(source).parse_timeline_only()
    }

    pub fn parse_requirement(source: &str) -> Result<RequirementAst, ParseError> {
        DiagramParser::new(source).parse_requirement_only()
    }

    pub fn parse_c4(source: &str) -> Result<C4Ast, ParseError> {
        DiagramParser::new(source).parse_c4_only()
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

    pub fn parse_gantt_header(source: &str) -> Result<GanttHeader, ParseError> {
        GanttHeaderParser::new(source).parse()
    }

    pub fn parse_gantt_statement(source: &str) -> Result<GanttStatement, ParseError> {
        GanttStatementParser::new(source).parse()
    }

    pub fn parse_pie_header(source: &str) -> Result<PieHeader, ParseError> {
        PieHeaderParser::new(source).parse()
    }

    pub fn parse_pie_statement(source: &str) -> Result<PieStatement, ParseError> {
        PieStatementParser::new(source).parse()
    }

    pub fn parse_quadrant_header(source: &str) -> Result<QuadrantHeader, ParseError> {
        QuadrantHeaderParser::new(source).parse()
    }

    pub fn parse_quadrant_statement(source: &str) -> Result<QuadrantStatement, ParseError> {
        QuadrantStatementParser::new(source).parse()
    }

    pub fn parse_zenuml_header(source: &str) -> Result<ZenUmlHeader, ParseError> {
        ZenUmlHeaderParser::new(source).parse()
    }

    pub fn parse_zenuml_statement(source: &str) -> Result<ZenUmlStatement, ParseError> {
        ZenUmlStatementParser::new(source, 0).parse()
    }

    pub fn parse_sankey_header(source: &str) -> Result<SankeyHeader, ParseError> {
        SankeyHeaderParser::new(source).parse()
    }

    pub fn parse_sankey_statement(source: &str) -> Result<SankeyStatement, ParseError> {
        SankeyStatementParser::new(source).parse()
    }

    pub fn parse_xy_chart_header(source: &str) -> Result<XyChartHeader, ParseError> {
        XyChartHeaderParser::new(source).parse()
    }

    pub fn parse_xy_chart_statement(source: &str) -> Result<XyChartStatement, ParseError> {
        XyChartStatementParser::new(source).parse()
    }

    pub fn parse_block_header(source: &str) -> Result<BlockDiagramHeader, ParseError> {
        BlockHeaderParser::new(source).parse()
    }

    pub fn parse_packet_header(source: &str) -> Result<PacketHeader, ParseError> {
        PacketHeaderParser::new(source).parse()
    }

    pub fn parse_packet_statement(source: &str) -> Result<PacketStatement, ParseError> {
        PacketStatementParser::new(source, 0).parse()
    }

    pub fn parse_kanban_header(source: &str) -> Result<KanbanHeader, ParseError> {
        KanbanHeaderParser::new(source).parse()
    }

    pub fn parse_architecture_header(source: &str) -> Result<ArchitectureHeader, ParseError> {
        ArchitectureHeaderParser::new(source).parse()
    }

    pub fn parse_architecture_statement(source: &str) -> Result<ArchitectureStatement, ParseError> {
        ArchitectureStatementParser::new(source).parse()
    }

    pub fn parse_radar_header(source: &str) -> Result<RadarHeader, ParseError> {
        RadarHeaderParser::new(source).parse()
    }

    pub fn parse_radar_statements(source: &str) -> Result<Vec<RadarStatement>, ParseError> {
        RadarStatementParser::new(source).parse()
    }

    pub fn parse_event_modeling_header(source: &str) -> Result<EventModelingHeader, ParseError> {
        EventModelingHeaderParser::new(source).parse()
    }

    pub fn parse_event_modeling_statement(
        source: &str,
    ) -> Result<EventModelingStatement, ParseError> {
        EventModelingStatementParser::new(source).parse()
    }

    pub fn parse_treemap_header(source: &str) -> Result<TreemapHeader, ParseError> {
        TreemapHeaderParser::new(source).parse()
    }

    pub fn parse_treemap_statement(source: &str) -> Result<TreemapStatement, ParseError> {
        TreemapStatementParser::new(source).parse()
    }

    pub fn parse_venn_header(source: &str) -> Result<VennHeader, ParseError> {
        VennHeaderParser::new(source).parse()
    }

    pub fn parse_venn_statement(source: &str) -> Result<VennStatement, ParseError> {
        VennStatementParser::new(source).parse()
    }

    pub fn parse_ishikawa_header(source: &str) -> Result<IshikawaHeader, ParseError> {
        IshikawaHeaderParser::new(source).parse()
    }

    pub fn parse_ishikawa_statement(source: &str) -> Result<IshikawaStatement, ParseError> {
        IshikawaStatementParser::new(source).parse()
    }

    pub fn parse_wardley_header(source: &str) -> Result<WardleyHeader, ParseError> {
        WardleyHeaderParser::new(source).parse()
    }

    pub fn parse_wardley_statement(source: &str) -> Result<WardleyStatement, ParseError> {
        WardleyStatementParser::new(source).parse()
    }

    pub fn parse_mindmap_header(source: &str) -> Result<MindmapHeader, ParseError> {
        MindmapHeaderParser::new(source).parse()
    }

    pub fn parse_journey_header(source: &str) -> Result<JourneyHeader, ParseError> {
        JourneyHeaderParser::new(source).parse()
    }

    pub fn parse_journey_statement(source: &str) -> Result<JourneyStatement, ParseError> {
        JourneyStatementParser::new(source).parse()
    }

    pub fn parse_gitgraph_header(source: &str) -> Result<GitGraphHeader, ParseError> {
        GitGraphHeaderParser::new(source).parse()
    }

    pub fn parse_gitgraph_statement(source: &str) -> Result<GitGraphStatement, ParseError> {
        GitGraphStatementParser::new(source).parse()
    }

    pub fn parse_timeline_header(source: &str) -> Result<TimelineHeader, ParseError> {
        TimelineHeaderParser::new(source).parse()
    }

    pub fn parse_timeline_statement(source: &str) -> Result<TimelineStatement, ParseError> {
        TimelineStatementParser::new(source).parse()
    }

    pub fn parse_requirement_header(source: &str) -> Result<RequirementHeader, ParseError> {
        RequirementHeaderParser::new(source).parse()
    }

    pub fn parse_requirement_statement(source: &str) -> Result<RequirementStatement, ParseError> {
        RequirementStatementParser::new(source).parse()
    }

    pub fn parse_c4_header(source: &str) -> Result<C4Header, ParseError> {
        C4HeaderParser::new(source).parse()
    }

    pub fn parse_c4_statement(source: &str) -> Result<C4Statement, ParseError> {
        C4StatementParser::new(source).parse()
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
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedDiagramHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;

        if let Ok(flow_header) = Parser::parse_flowchart_header(header.text) {
            reject_unsupported_flowchart_config_directives(&self.directives)?;
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
            reject_unsupported_state_config_directives(&self.directives)?;
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
        if let Ok(gantt_header) = Parser::parse_gantt_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_gantt_body(shift_gantt_header(gantt_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Gantt(Box::new(ast))));
        }
        if let Ok(pie_header) = Parser::parse_pie_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_pie_body(shift_pie_header(pie_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Pie(Box::new(ast))));
        }
        if let Ok(quadrant_header) = Parser::parse_quadrant_header(header.text) {
            self.cursor = header.line.next;
            let ast =
                self.parse_quadrant_body(shift_quadrant_header(quadrant_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Quadrant(Box::new(ast))));
        }
        if let Ok(zenuml_header) = Parser::parse_zenuml_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_zenuml_body(shift_zenuml_header(zenuml_header, header.start))?;
            return Ok(self.diagram(DiagramKind::ZenUml(Box::new(ast))));
        }
        if let Ok(sankey_header) = Parser::parse_sankey_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_sankey_body(shift_sankey_header(sankey_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Sankey(Box::new(ast))));
        }
        if let Ok(xy_header) = Parser::parse_xy_chart_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_xy_chart_body(shift_xy_chart_header(xy_header, header.start))?;
            return Ok(self.diagram(DiagramKind::XyChart(Box::new(ast))));
        }
        if let Ok(block_header) = Parser::parse_block_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_block_body(shift_block_header(block_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Block(Box::new(ast))));
        }
        if let Ok(packet_header) = Parser::parse_packet_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_packet_body(shift_packet_header(packet_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Packet(Box::new(ast))));
        }
        if let Ok(kanban_header) = Parser::parse_kanban_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_kanban_body(shift_kanban_header(kanban_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Kanban(Box::new(ast))));
        }
        if let Ok(architecture_header) = Parser::parse_architecture_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_architecture_body(shift_architecture_header(
                architecture_header,
                header.start,
            ))?;
            return Ok(self.diagram(DiagramKind::Architecture(Box::new(ast))));
        }
        if let Ok(radar_header) = Parser::parse_radar_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_radar_body(shift_radar_header(radar_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Radar(Box::new(ast))));
        }
        if let Ok(event_modeling_header) = Parser::parse_event_modeling_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_event_modeling_body(shift_event_modeling_header(
                event_modeling_header,
                header.start,
            ))?;
            return Ok(self.diagram(DiagramKind::EventModeling(Box::new(ast))));
        }
        if let Ok(treemap_header) = Parser::parse_treemap_header(header.text) {
            self.cursor = header.line.next;
            let ast =
                self.parse_treemap_body(shift_treemap_header(treemap_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Treemap(Box::new(ast))));
        }
        if let Ok(venn_header) = Parser::parse_venn_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_venn_body(shift_venn_header(venn_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Venn(Box::new(ast))));
        }
        if let Ok(ishikawa_header) = Parser::parse_ishikawa_header(header.text) {
            self.cursor = header.line.next;
            let ast =
                self.parse_ishikawa_body(shift_ishikawa_header(ishikawa_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Ishikawa(Box::new(ast))));
        }
        if let Ok(wardley_header) = Parser::parse_wardley_header(header.text) {
            self.cursor = header.line.next;
            let ast =
                self.parse_wardley_body(shift_wardley_header(wardley_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Wardley(Box::new(ast))));
        }
        if let Ok(mindmap_header) = Parser::parse_mindmap_header(header.text) {
            self.cursor = header.line.next;
            let ast =
                self.parse_mindmap_body(shift_mindmap_header(mindmap_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Mindmap(Box::new(ast))));
        }
        if let Ok(journey_header) = Parser::parse_journey_header(header.text) {
            self.cursor = header.line.next;
            let ast =
                self.parse_journey_body(shift_journey_header(journey_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Journey(Box::new(ast))));
        }
        if let Ok(gitgraph_header) = Parser::parse_gitgraph_header(header.text) {
            self.cursor = header.line.next;
            let ast =
                self.parse_gitgraph_body(shift_gitgraph_header(gitgraph_header, header.start))?;
            return Ok(self.diagram(DiagramKind::GitGraph(Box::new(ast))));
        }
        if let Ok(timeline_header) = Parser::parse_timeline_header(header.text) {
            self.cursor = header.line.next;
            let ast =
                self.parse_timeline_body(shift_timeline_header(timeline_header, header.start))?;
            return Ok(self.diagram(DiagramKind::Timeline(Box::new(ast))));
        }
        if let Ok(requirement_header) = Parser::parse_requirement_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_requirement_body(shift_requirement_header(
                requirement_header,
                header.start,
            ))?;
            return Ok(self.diagram(DiagramKind::Requirement(Box::new(ast))));
        }
        if let Ok(c4_header) = Parser::parse_c4_header(header.text) {
            self.cursor = header.line.next;
            let ast = self.parse_c4_body(shift_c4_header(c4_header, header.start))?;
            return Ok(self.diagram(DiagramKind::C4(Box::new(ast))));
        }

        Err(ParseError {
            kind: ParseErrorKind::ExpectedDiagramHeader,
            span: Span::new(header.start, header.end),
        })
    }

    fn parse_flowchart_only(mut self) -> Result<FlowchartAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedFlowchartDirective,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let flow_header = Parser::parse_flowchart_header(header.text)?;
        reject_unsupported_flowchart_config_directives(&self.directives)?;
        self.cursor = header.line.next;
        self.parse_flowchart_body(shift_flowchart_header(flow_header, header.start))
    }

    fn parse_sequence_only(mut self) -> Result<SequenceAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
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
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedStateHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let state_header = Parser::parse_state_header(header.text)?;
        reject_unsupported_state_config_directives(&self.directives)?;
        self.cursor = header.line.next;
        self.parse_state_body(shift_state_header(state_header, header.start))
    }

    fn parse_class_only(mut self) -> Result<ClassAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
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
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedErHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let er_header = Parser::parse_er_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_er_body(shift_er_header(er_header, header.start))
    }

    fn parse_gantt_only(mut self) -> Result<GanttAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedGanttHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let gantt_header = Parser::parse_gantt_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_gantt_body(shift_gantt_header(gantt_header, header.start))
    }

    fn parse_pie_only(mut self) -> Result<PieAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedPieHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let pie_header = Parser::parse_pie_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_pie_body(shift_pie_header(pie_header, header.start))
    }

    fn parse_quadrant_only(mut self) -> Result<QuadrantAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedQuadrantHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let quadrant_header = Parser::parse_quadrant_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_quadrant_body(shift_quadrant_header(quadrant_header, header.start))
    }

    fn parse_zenuml_only(mut self) -> Result<ZenUmlAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedZenUmlHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let zenuml_header = Parser::parse_zenuml_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_zenuml_body(shift_zenuml_header(zenuml_header, header.start))
    }

    fn parse_sankey_only(mut self) -> Result<SankeyAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedSankeyHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let sankey_header = Parser::parse_sankey_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_sankey_body(shift_sankey_header(sankey_header, header.start))
    }

    fn parse_xy_chart_only(mut self) -> Result<XyChartAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedXyChartHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let xy_header = Parser::parse_xy_chart_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_xy_chart_body(shift_xy_chart_header(xy_header, header.start))
    }

    fn parse_block_only(mut self) -> Result<BlockDiagramAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedBlockHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let block_header = Parser::parse_block_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_block_body(shift_block_header(block_header, header.start))
    }

    fn parse_packet_only(mut self) -> Result<PacketAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedPacketHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let packet_header = Parser::parse_packet_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_packet_body(shift_packet_header(packet_header, header.start))
    }

    fn parse_kanban_only(mut self) -> Result<KanbanAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedKanbanHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let kanban_header = Parser::parse_kanban_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_kanban_body(shift_kanban_header(kanban_header, header.start))
    }

    fn parse_architecture_only(mut self) -> Result<ArchitectureAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let architecture_header = Parser::parse_architecture_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_architecture_body(shift_architecture_header(architecture_header, header.start))
    }

    fn parse_radar_only(mut self) -> Result<RadarAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedRadarHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let radar_header = Parser::parse_radar_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_radar_body(shift_radar_header(radar_header, header.start))
    }

    fn parse_event_modeling_only(mut self) -> Result<EventModelingAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedEventModelingHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let event_modeling_header = Parser::parse_event_modeling_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_event_modeling_body(shift_event_modeling_header(
            event_modeling_header,
            header.start,
        ))
    }

    fn parse_treemap_only(mut self) -> Result<TreemapAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedTreemapHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let treemap_header = Parser::parse_treemap_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_treemap_body(shift_treemap_header(treemap_header, header.start))
    }

    fn parse_venn_only(mut self) -> Result<VennAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedVennHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let venn_header = Parser::parse_venn_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_venn_body(shift_venn_header(venn_header, header.start))
    }

    fn parse_ishikawa_only(mut self) -> Result<IshikawaAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedIshikawaHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let ishikawa_header = Parser::parse_ishikawa_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_ishikawa_body(shift_ishikawa_header(ishikawa_header, header.start))
    }

    fn parse_wardley_only(mut self) -> Result<WardleyAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedWardleyHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let wardley_header = Parser::parse_wardley_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_wardley_body(shift_wardley_header(wardley_header, header.start))
    }

    fn parse_mindmap_only(mut self) -> Result<MindmapAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedMindmapHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let mindmap_header = Parser::parse_mindmap_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_mindmap_body(shift_mindmap_header(mindmap_header, header.start))
    }

    fn parse_journey_only(mut self) -> Result<JourneyAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedJourneyHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let journey_header = Parser::parse_journey_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_journey_body(shift_journey_header(journey_header, header.start))
    }

    fn parse_gitgraph_only(mut self) -> Result<GitGraphAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedGitGraphHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let gitgraph_header = Parser::parse_gitgraph_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_gitgraph_body(shift_gitgraph_header(gitgraph_header, header.start))
    }

    fn parse_timeline_only(mut self) -> Result<TimelineAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedTimelineHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let timeline_header = Parser::parse_timeline_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_timeline_body(shift_timeline_header(timeline_header, header.start))
    }

    fn parse_requirement_only(mut self) -> Result<RequirementAst, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedRequirementHeader,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let requirement_header = Parser::parse_requirement_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_requirement_body(shift_requirement_header(requirement_header, header.start))
    }

    fn parse_c4_only(mut self) -> Result<C4Ast, ParseError> {
        self.skip_preamble();
        self.reject_frontmatter()?;
        let header = self.current_trimmed_line().ok_or(ParseError {
            kind: ParseErrorKind::ExpectedC4Header,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let c4_header = Parser::parse_c4_header(header.text)?;
        self.cursor = header.line.next;
        self.parse_c4_body(shift_c4_header(c4_header, header.start))
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

    fn reject_frontmatter(&self) -> Result<(), ParseError> {
        let Some(line) = self.current_trimmed_line() else {
            return Ok(());
        };
        if line.text != "---" {
            return Ok(());
        }
        let mut cursor = line.line.next;
        let mut end = line.end;
        while let Some(next) = source_line(self.source, cursor) {
            end = next.next;
            if let Some((trim_start, trim_end)) = trim_ascii_range(next.text)
                && &next.text[trim_start..trim_end] == "---"
            {
                end = next.start + trim_end;
                break;
            }
            cursor = next.next;
        }
        Err(ParseError {
            kind: ParseErrorKind::UnsupportedMermaidConfig,
            span: Span::new(line.start, end),
        })
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
        let mut box_stack = Vec::<(usize, usize)>::new();

        while let Some(line) = self.current_trimmed_line() {
            if line.text == "end" {
                box_stack.pop();
                self.cursor = line.line.next;
                continue;
            }
            let statement = shift_sequence_statement(
                Parser::parse_sequence_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            match &statement {
                SequenceStatement::Participant(participant) => {
                    ast.participants.push((**participant).clone());
                    push_sequence_box_participant(&mut ast, &box_stack, participant.id.clone());
                }
                SequenceStatement::Create(create) => {
                    ast.participants.push(create.participant.clone());
                    push_sequence_box_participant(
                        &mut ast,
                        &box_stack,
                        create.participant.id.clone(),
                    );
                }
                SequenceStatement::Box(sequence_box) => {
                    let box_index = ast.boxes.len();
                    let statement_index = ast.statements.len();
                    ast.boxes.push((**sequence_box).clone());
                    ast.statements.push(statement);
                    box_stack.push((box_index, statement_index));
                    self.cursor = line.line.next;
                    continue;
                }
                SequenceStatement::Destroy(_)
                | SequenceStatement::Message(_)
                | SequenceStatement::ActivationStart(_)
                | SequenceStatement::ActivationEnd(_)
                | SequenceStatement::Note(_)
                | SequenceStatement::Control(_)
                | SequenceStatement::AutoNumber(_)
                | SequenceStatement::Comment(_)
                | SequenceStatement::Directive(_) => {}
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
            let statement = shift_state_statement(
                Parser::parse_state_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            match &statement {
                StateStatement::State(state) | StateStatement::Composite(state) => {
                    ast.states.push((**state).clone());
                }
                StateStatement::Transition(transition) => {
                    ast.transitions.push((**transition).clone());
                }
                StateStatement::ClassDef(class_def) => ast.classes.push(class_def.clone()),
                StateStatement::Direction(direction) => ast.direction = Some(*direction),
                StateStatement::Directive(directive) => {
                    reject_unsupported_state_config_directive(directive)?;
                }
                StateStatement::ClassApply(_) | StateStatement::Comment(_) => {}
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
            let statement = shift_class_statement(
                Parser::parse_class_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
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
                    parse_class_member(line.text, 0, line.text.len())
                        .map_err(|error| shift_error(error, line.start))?,
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
            let statement = shift_er_statement(
                Parser::parse_er_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
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
                parse_er_attribute(line.text, 0, line.text.len())
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            ));
            self.cursor = line.line.next;
        }

        Err(ParseError {
            kind: ParseErrorKind::ExpectedErAttribute,
            span: Span::new(entity.span.start, self.source.len()),
        })
    }

    fn parse_gantt_body(&mut self, header: GanttHeader) -> Result<GanttAst, ParseError> {
        let mut ast = GanttAst {
            header,
            title: None,
            date_format: None,
            axis_format: None,
            statements: Vec::new(),
            tasks: Vec::new(),
            span: Span::new(header.span.start, self.source.len()),
        };
        let mut current_section = None;

        while let Some(line) = self.current_trimmed_line() {
            let mut statement = shift_gantt_statement(
                Parser::parse_gantt_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            if let GanttStatement::Task(task) = &mut statement {
                task.section = current_section.clone();
            }
            if let GanttStatement::Section(section) = &statement {
                current_section = Some(section.clone());
            }
            push_gantt_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_pie_body(&mut self, header: PieHeader) -> Result<PieAst, ParseError> {
        let span_start = header.span.start;
        let mut config = PieConfig::default_values();
        apply_pie_config_directives(&mut config, &self.directives);
        let mut ast = PieAst {
            title: header.title.clone(),
            show_data: header.show_data,
            config,
            header,
            statements: Vec::new(),
            slices: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            let statement = shift_pie_statement(
                Parser::parse_pie_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            if let PieStatement::Directive(directive) = &statement {
                apply_pie_config_directive(&mut ast.config, directive);
            }
            push_pie_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_quadrant_body(&mut self, header: QuadrantHeader) -> Result<QuadrantAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = QuadrantAst {
            header,
            title: None,
            x_axis: None,
            y_axis: None,
            quadrants: Vec::new(),
            points: Vec::new(),
            classes: Vec::new(),
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            let statement = shift_quadrant_statement(
                Parser::parse_quadrant_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            push_quadrant_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_zenuml_body(&mut self, header: ZenUmlHeader) -> Result<ZenUmlAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = ZenUmlAst {
            header,
            title: None,
            participants: Vec::new(),
            messages: Vec::new(),
            fragments: Vec::new(),
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };
        let mut depth = 0u16;

        while let Some(line) = self.current_trimmed_line() {
            let mut start = line.start;
            let mut text = line.text;
            let mut closed_only = false;
            loop {
                let leading = text.len() - text.trim_start().len();
                start += leading;
                text = text.trim_start();
                if !text.starts_with('}') {
                    break;
                }
                depth = depth.saturating_sub(1);
                let close_span = Span::new(start, start + 1);
                start += 1;
                text = &text[1..];
                if text.trim().is_empty() {
                    ast.statements.push(ZenUmlStatement::BlockEnd(close_span));
                    closed_only = true;
                    break;
                }
            }
            if closed_only {
                self.cursor = line.line.next;
                continue;
            }
            let trimmed_end = text.trim_end();
            let opens_block = trimmed_end.ends_with('{');
            let statement_text = if opens_block {
                trimmed_end[..trimmed_end.len() - 1].trim_end()
            } else {
                trimmed_end
            };
            if !statement_text.is_empty() {
                let statement = shift_zenuml_statement(
                    ZenUmlStatementParser::new(statement_text, depth)
                        .parse()
                        .map_err(|error| shift_error(error, start))?,
                    start,
                );
                push_zenuml_statement(&mut ast, statement);
            }
            if opens_block {
                depth = depth.saturating_add(1);
            }
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_sankey_body(&mut self, header: SankeyHeader) -> Result<SankeyAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = SankeyAst {
            header,
            links: Vec::new(),
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            let statement = shift_sankey_statement(
                Parser::parse_sankey_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            push_sankey_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_xy_chart_body(&mut self, header: XyChartHeader) -> Result<XyChartAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = XyChartAst {
            header,
            title: None,
            x_axis: None,
            y_axis: None,
            series: Vec::new(),
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            let statement = shift_xy_chart_statement(
                Parser::parse_xy_chart_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            push_xy_chart_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_block_body(
        &mut self,
        header: BlockDiagramHeader,
    ) -> Result<BlockDiagramAst, ParseError> {
        let span_start = header.span.start;
        let statements = self.parse_block_statements(false)?;
        let mut ast = BlockDiagramAst {
            header,
            statements,
            blocks: Vec::new(),
            edges: Vec::new(),
            classes: Vec::new(),
            styles: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };
        for statement in ast.statements.clone() {
            push_block_statement(&mut ast, statement);
        }
        Ok(ast)
    }

    fn parse_block_statements(
        &mut self,
        stop_at_end: bool,
    ) -> Result<Vec<BlockStatement>, ParseError> {
        let mut statements = Vec::new();
        while let Some(line) = self.current_trimmed_line() {
            if line.text == "end" {
                if stop_at_end {
                    self.cursor = line.line.next;
                    return Ok(statements);
                }
                return Err(ParseError {
                    kind: ParseErrorKind::UnknownBlockStatement,
                    span: Span::new(line.start, line.end),
                });
            }
            if let Some(mut container) = parse_block_container_header(line.text)
                .map_err(|error| shift_error(error, line.start))?
            {
                self.cursor = line.line.next;
                container.statements = self.parse_block_statements(true)?;
                container.span = Span::new(line.start + container.span.start, self.cursor);
                statements.push(BlockStatement::Container(Box::new(
                    shift_block_container_header_only(container, line.start),
                )));
                continue;
            }
            let mut line_statements = parse_block_line_statements(line.text)
                .map_err(|error| shift_error(error, line.start))?
                .into_iter()
                .map(|statement| shift_block_statement(statement, line.start))
                .collect::<Vec<_>>();
            statements.append(&mut line_statements);
            self.cursor = line.line.next;
        }
        if stop_at_end {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownBlockStatement,
                span: Span::new(self.source.len(), self.source.len()),
            });
        }
        Ok(statements)
    }

    fn parse_packet_body(&mut self, header: PacketHeader) -> Result<PacketAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = PacketAst {
            header,
            title: None,
            fields: Vec::new(),
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };
        let mut next_bit = 0u32;

        while let Some(line) = self.current_trimmed_line() {
            let statement = shift_packet_statement(
                PacketStatementParser::new(line.text, next_bit)
                    .parse()
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            if let PacketStatement::Field(field) = &statement {
                next_bit = field.range.end.value.saturating_add(1);
            }
            push_packet_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_kanban_body(&mut self, header: KanbanHeader) -> Result<KanbanAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = KanbanAst {
            header,
            columns: Vec::new(),
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };
        let mut current_column: Option<(usize, usize, usize)> = None;

        while let Some(line) = source_line(self.source, self.cursor) {
            self.cursor = line.next;
            let Some((trim_start, trim_end)) = trim_ascii_range(line.text) else {
                continue;
            };
            let start = line.start + trim_start;
            let end = line.start + trim_end;
            let text = &self.source[start..end];
            if let Ok(directive) = Parser::parse_mermaid_directive(text) {
                ast.statements
                    .push(KanbanStatement::Directive(shift_directive(
                        directive, start,
                    )));
                continue;
            }
            if let Ok(comment) = Parser::parse_mermaid_comment(text) {
                ast.statements
                    .push(KanbanStatement::Comment(shift_comment(comment, start)));
                continue;
            }
            let item = shift_kanban_item(
                parse_kanban_item(line.text, trim_start, trim_end)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            let is_task = current_column.is_some_and(|(_, indent, _)| trim_start > indent);
            if is_task {
                let task = item.into_task();
                if let Some((column_index, _, statement_index)) = current_column {
                    ast.columns[column_index].span =
                        Span::new(ast.columns[column_index].span.start, task.span.end);
                    ast.columns[column_index].tasks.push(task.clone());
                    if let Some(KanbanStatement::Column(column)) =
                        ast.statements.get_mut(statement_index)
                    {
                        column.span = ast.columns[column_index].span;
                        column.tasks.push(task);
                    }
                }
                continue;
            }
            let column = item.into_column();
            ast.columns.push(column.clone());
            let column_index = ast.columns.len() - 1;
            let statement_index = ast.statements.len();
            ast.statements
                .push(KanbanStatement::Column(Box::new(column)));
            current_column = Some((column_index, trim_start, statement_index));
        }

        Ok(ast)
    }

    fn parse_architecture_body(
        &mut self,
        header: ArchitectureHeader,
    ) -> Result<ArchitectureAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = ArchitectureAst {
            header,
            groups: Vec::new(),
            services: Vec::new(),
            junctions: Vec::new(),
            edges: Vec::new(),
            alignments: Vec::new(),
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            let statement = shift_architecture_statement(
                Parser::parse_architecture_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            push_architecture_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_radar_body(&mut self, header: RadarHeader) -> Result<RadarAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = RadarAst {
            header,
            title: None,
            axes: Vec::new(),
            curves: Vec::new(),
            options: Vec::new(),
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            let statements = Parser::parse_radar_statements(line.text)
                .map_err(|error| shift_error(error, line.start))?
                .into_iter()
                .map(|statement| shift_radar_statement(statement, line.start))
                .collect::<Vec<_>>();
            for statement in statements {
                push_radar_statement(&mut ast, statement);
            }
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_event_modeling_body(
        &mut self,
        header: EventModelingHeader,
    ) -> Result<EventModelingAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = EventModelingAst {
            header,
            timeframes: Vec::new(),
            data_blocks: Vec::new(),
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            let statement = shift_event_modeling_statement(
                Parser::parse_event_modeling_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            push_event_modeling_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_treemap_body(&mut self, header: TreemapHeader) -> Result<TreemapAst, ParseError> {
        let span_start = header.span.start;
        let mut parsed = Vec::<ParsedTreemapNode>::new();
        let mut roots = Vec::<usize>::new();
        let mut stack = Vec::<(usize, usize)>::new();
        let mut statements = Vec::new();
        let mut classes = Vec::new();

        while let Some(line) = self.current_trimmed_line() {
            let indent = line.start.saturating_sub(line.line.start);
            if let Ok(directive) = Parser::parse_mermaid_directive(line.text) {
                statements.push(TreemapStatement::Directive(shift_directive(
                    directive, line.start,
                )));
                self.cursor = line.line.next;
                continue;
            }
            if let Ok(comment) = Parser::parse_mermaid_comment(line.text) {
                statements.push(TreemapStatement::Comment(shift_comment(
                    comment, line.start,
                )));
                self.cursor = line.line.next;
                continue;
            }
            if has_keyword(line.text, 0, "classDef") {
                let class_def = shift_class_def(
                    Parser::parse_flow_class_def(line.text)
                        .map_err(|error| shift_error(error, line.start))?,
                    line.start,
                );
                classes.push(class_def.clone());
                statements.push(TreemapStatement::ClassDef(class_def));
                self.cursor = line.line.next;
                continue;
            }
            while stack.last().is_some_and(|(level, _)| *level >= indent) {
                stack.pop();
            }
            let parent = stack.last().map(|(_, index)| *index);
            let index = parsed.len();
            let node = shift_treemap_node(
                parse_treemap_node(line.text).map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            if let Some(parent) = parent {
                parsed[parent].children.push(index);
            } else {
                roots.push(index);
            }
            parsed.push(ParsedTreemapNode {
                node,
                children: Vec::new(),
            });
            stack.push((indent, index));
            self.cursor = line.line.next;
        }

        let roots = roots
            .into_iter()
            .map(|index| build_treemap_node(index, &parsed))
            .collect::<Vec<_>>();
        for root in &roots {
            statements.push(TreemapStatement::Node(Box::new(root.clone())));
        }

        Ok(TreemapAst {
            header,
            statements,
            roots,
            classes,
            span: Span::new(span_start, self.source.len()),
        })
    }

    fn parse_venn_body(&mut self, header: VennHeader) -> Result<VennAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = VennAst {
            header,
            title: None,
            sets: Vec::new(),
            unions: Vec::new(),
            texts: Vec::new(),
            styles: Vec::new(),
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };
        let mut current_owner = None::<VennTextOwner>;

        while let Some(line) = self.current_trimmed_line() {
            let mut statement = shift_venn_statement(
                Parser::parse_venn_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            match &mut statement {
                VennStatement::Set(set) => {
                    current_owner = Some(VennTextOwner::Set(set.id.value.clone()));
                    ast.sets.push((**set).clone());
                }
                VennStatement::Union(union) => {
                    let members = union
                        .members
                        .iter()
                        .map(|member| member.value.clone())
                        .collect::<Vec<_>>();
                    current_owner = Some(VennTextOwner::Union(members));
                    ast.unions.push((**union).clone());
                }
                VennStatement::Text(text) => {
                    text.owner = current_owner.clone();
                    if let Some(owner) = &text.owner {
                        attach_venn_text(&mut ast, owner, (**text).clone());
                    }
                    ast.texts.push((**text).clone());
                }
                VennStatement::Title(title) => ast.title = Some(title.clone()),
                VennStatement::Style(style) => ast.styles.push(style.clone()),
                VennStatement::Comment(_) | VennStatement::Directive(_) => {}
            }
            ast.statements.push(statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_ishikawa_body(&mut self, header: IshikawaHeader) -> Result<IshikawaAst, ParseError> {
        let span_start = header.span.start;
        let mut event = None::<Label>;
        let mut parsed = Vec::<ParsedIshikawaNode>::new();
        let mut roots = Vec::<usize>::new();
        let mut stack = Vec::<(usize, usize)>::new();
        let mut statements = Vec::new();

        while let Some(line) = self.current_trimmed_line() {
            if let Ok(directive) = Parser::parse_mermaid_directive(line.text) {
                statements.push(IshikawaStatement::Directive(shift_directive(
                    directive, line.start,
                )));
                self.cursor = line.line.next;
                continue;
            }
            if let Ok(comment) = Parser::parse_mermaid_comment(line.text) {
                statements.push(IshikawaStatement::Comment(shift_comment(
                    comment, line.start,
                )));
                self.cursor = line.line.next;
                continue;
            }

            if event.is_none() {
                let label = parse_ishikawa_label(
                    line.text,
                    line.start,
                    ParseErrorKind::ExpectedIshikawaEvent,
                )?;
                statements.push(IshikawaStatement::Event(label.clone()));
                event = Some(label);
                self.cursor = line.line.next;
                continue;
            }

            let indent = line.start.saturating_sub(line.line.start);
            while stack.last().is_some_and(|(level, _)| *level >= indent) {
                stack.pop();
            }
            let parent = stack.last().map(|(_, index)| *index);
            let index = parsed.len();
            let node = parse_ishikawa_node(line.text, line.start)?;
            if let Some(parent) = parent {
                parsed[parent].children.push(index);
            } else {
                roots.push(index);
            }
            parsed.push(ParsedIshikawaNode {
                node,
                children: Vec::new(),
            });
            stack.push((indent, index));
            self.cursor = line.line.next;
        }

        let event = event.ok_or(ParseError {
            kind: ParseErrorKind::ExpectedIshikawaEvent,
            span: Span::new(self.source.len(), self.source.len()),
        })?;
        let causes = roots
            .into_iter()
            .map(|index| build_ishikawa_node(index, &parsed))
            .collect::<Vec<_>>();
        for cause in &causes {
            statements.push(IshikawaStatement::Cause(Box::new(cause.clone())));
        }

        Ok(IshikawaAst {
            header,
            event,
            causes,
            statements,
            span: Span::new(span_start, self.source.len()),
        })
    }

    fn parse_wardley_body(&mut self, header: WardleyHeader) -> Result<WardleyAst, ParseError> {
        let span_start = header.span.start;
        let mut ast = WardleyAst {
            header,
            title: None,
            size: None,
            components: Vec::new(),
            links: Vec::new(),
            evolves: Vec::new(),
            notes: Vec::new(),
            annotations_position: None,
            annotations: Vec::new(),
            forces: Vec::new(),
            evolution: None,
            statements: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };
        let mut pipeline = None::<Label>;

        while let Some(line) = self.current_trimmed_line() {
            if line.text == "}" {
                pipeline = None;
                self.cursor = line.line.next;
                continue;
            }
            let mut statement = shift_wardley_statement(
                Parser::parse_wardley_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            if let WardleyStatement::Component(component) = &mut statement
                && component.pipeline.is_none()
                && let Some(parent) = &pipeline
            {
                component.pipeline = Some(parent.clone());
            }
            match &statement {
                WardleyStatement::Title(title) => ast.title = Some(title.clone()),
                WardleyStatement::Size(size) => ast.size = Some(*size),
                WardleyStatement::Component(component) => {
                    ast.components.push((**component).clone())
                }
                WardleyStatement::Link(link) => ast.links.push(link.clone()),
                WardleyStatement::Evolve(evolve) => ast.evolves.push(evolve.clone()),
                WardleyStatement::Note(note) => ast.notes.push(note.clone()),
                WardleyStatement::Annotations(coord) => {
                    ast.annotations_position = Some(coord.clone());
                }
                WardleyStatement::Annotation(annotation) => {
                    ast.annotations.push(annotation.clone());
                }
                WardleyStatement::Force(force) => ast.forces.push(force.clone()),
                WardleyStatement::Evolution(evolution) => ast.evolution = Some(evolution.clone()),
                WardleyStatement::Pipeline(_)
                | WardleyStatement::Comment(_)
                | WardleyStatement::Directive(_) => {}
            }
            if let Some(next_pipeline) = wardley_pipeline_start(line.text, line.start)? {
                pipeline = Some(next_pipeline);
            }
            ast.statements.push(statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_mindmap_body(&mut self, header: MindmapHeader) -> Result<MindmapAst, ParseError> {
        let span_start = header.span.start;
        let mut parsed = Vec::<ParsedMindmapNode>::new();
        let mut roots = Vec::<usize>::new();
        let mut stack = Vec::<(usize, usize)>::new();
        let mut statements = Vec::new();

        while let Some(line) = self.current_trimmed_line() {
            let indent = line.start.saturating_sub(line.line.start);
            let trimmed = line.text;
            if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
                statements.push(MindmapStatement::Directive(shift_directive(
                    directive, line.start,
                )));
                self.cursor = line.line.next;
                continue;
            }
            if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
                statements.push(MindmapStatement::Comment(shift_comment(
                    comment, line.start,
                )));
                self.cursor = line.line.next;
                continue;
            }
            if let Some(icon) = parse_mindmap_icon(trimmed, line.start)? {
                if let Some((_, index)) = stack.iter().rev().find(|(level, _)| *level <= indent) {
                    parsed[*index].node.icon = Some(icon);
                }
                self.cursor = line.line.next;
                continue;
            }
            if let Some(classes) = parse_mindmap_class_apply(trimmed, line.start)? {
                if let Some((_, index)) = stack.iter().rev().find(|(level, _)| *level <= indent) {
                    parsed[*index].node.classes.extend(classes);
                }
                self.cursor = line.line.next;
                continue;
            }
            while stack.last().is_some_and(|(level, _)| *level >= indent) {
                stack.pop();
            }
            let parent = stack.last().map(|(_, index)| *index);
            let index = parsed.len();
            let node = parse_mindmap_node(trimmed, line.start)?;
            if let Some(parent) = parent {
                parsed[parent].children.push(index);
            } else {
                roots.push(index);
            }
            parsed.push(ParsedMindmapNode {
                node,
                children: Vec::new(),
            });
            stack.push((indent, index));
            self.cursor = line.line.next;
        }

        let roots = roots
            .into_iter()
            .map(|index| build_mindmap_node(index, &parsed))
            .collect::<Vec<_>>();
        for root in &roots {
            statements.push(MindmapStatement::Node(Box::new(root.clone())));
        }

        Ok(MindmapAst {
            header,
            statements,
            roots,
            span: Span::new(span_start, self.source.len()),
        })
    }

    fn parse_journey_body(&mut self, header: JourneyHeader) -> Result<JourneyAst, ParseError> {
        let mut ast = JourneyAst {
            header,
            title: None,
            statements: Vec::new(),
            tasks: Vec::new(),
            span: Span::new(header.span.start, self.source.len()),
        };
        let mut current_section = None;

        while let Some(line) = self.current_trimmed_line() {
            let mut statement = shift_journey_statement(
                Parser::parse_journey_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            if let JourneyStatement::Task(task) = &mut statement {
                task.section = current_section.clone();
            }
            if let JourneyStatement::Section(section) = &statement {
                current_section = Some(section.clone());
            }
            push_journey_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_gitgraph_body(&mut self, header: GitGraphHeader) -> Result<GitGraphAst, ParseError> {
        let mut ast = GitGraphAst {
            header,
            statements: Vec::new(),
            commits: Vec::new(),
            branches: Vec::new(),
            merges: Vec::new(),
            cherry_picks: Vec::new(),
            span: Span::new(header.span.start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            let statement = shift_gitgraph_statement(
                Parser::parse_gitgraph_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            push_gitgraph_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_timeline_body(&mut self, header: TimelineHeader) -> Result<TimelineAst, ParseError> {
        let mut ast = TimelineAst {
            header,
            title: None,
            statements: Vec::new(),
            periods: Vec::new(),
            span: Span::new(header.span.start, self.source.len()),
        };
        let mut current_section = None;

        while let Some(line) = self.current_trimmed_line() {
            let mut statement = shift_timeline_statement(
                Parser::parse_timeline_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            if let TimelineStatement::Period(period) = &mut statement {
                period.section = current_section.clone();
            }
            if let TimelineStatement::Section(section) = &statement {
                current_section = Some(section.clone());
            }
            push_timeline_statement(&mut ast, statement)?;
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_requirement_body(
        &mut self,
        header: RequirementHeader,
    ) -> Result<RequirementAst, ParseError> {
        let mut ast = RequirementAst {
            header,
            direction: None,
            statements: Vec::new(),
            requirements: Vec::new(),
            elements: Vec::new(),
            relationships: Vec::new(),
            classes: Vec::new(),
            styles: Vec::new(),
            span: Span::new(header.span.start, self.source.len()),
        };

        while let Some(line) = self.current_trimmed_line() {
            if is_requirement_node_block_header(line.text) {
                let node = self.parse_requirement_node_block(line)?;
                push_requirement_statement(
                    &mut ast,
                    RequirementStatement::Requirement(Box::new(node)),
                );
                continue;
            }
            if is_requirement_element_block_header(line.text) {
                let element = self.parse_requirement_element_block(line)?;
                push_requirement_statement(
                    &mut ast,
                    RequirementStatement::Element(Box::new(element)),
                );
                continue;
            }
            if line.text == "}" {
                self.cursor = line.line.next;
                continue;
            }
            let statement = shift_requirement_statement(
                Parser::parse_requirement_statement(line.text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            push_requirement_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
    }

    fn parse_requirement_node_block(
        &mut self,
        header_line: TrimmedSourceLine<'source>,
    ) -> Result<RequirementNode, ParseError> {
        let mut node = parse_requirement_node_header(
            header_line.text,
            0,
            header_line.text.len().saturating_sub(1),
        )?;
        node = shift_requirement_node(node, header_line.start);
        self.cursor = header_line.line.next;

        while let Some(line) = self.current_trimmed_line() {
            if line.text == "}" {
                node.span = Span::new(node.span.start, line.end);
                self.cursor = line.line.next;
                return Ok(node);
            }
            if Parser::parse_mermaid_comment(line.text).is_ok()
                || Parser::parse_mermaid_directive(line.text).is_ok()
            {
                self.cursor = line.line.next;
                continue;
            }
            apply_requirement_field(&mut node, line.text, line.start)?;
            self.cursor = line.line.next;
        }

        Err(ParseError {
            kind: ParseErrorKind::ExpectedRequirementField,
            span: Span::new(node.span.start, self.source.len()),
        })
    }

    fn parse_requirement_element_block(
        &mut self,
        header_line: TrimmedSourceLine<'source>,
    ) -> Result<RequirementElement, ParseError> {
        let mut element = parse_requirement_element_header(
            header_line.text,
            0,
            header_line.text.len().saturating_sub(1),
        )?;
        element = shift_requirement_element(element, header_line.start);
        self.cursor = header_line.line.next;

        while let Some(line) = self.current_trimmed_line() {
            if line.text == "}" {
                element.span = Span::new(element.span.start, line.end);
                self.cursor = line.line.next;
                return Ok(element);
            }
            if Parser::parse_mermaid_comment(line.text).is_ok()
                || Parser::parse_mermaid_directive(line.text).is_ok()
            {
                self.cursor = line.line.next;
                continue;
            }
            apply_requirement_element_field(&mut element, line.text, line.start)?;
            self.cursor = line.line.next;
        }

        Err(ParseError {
            kind: ParseErrorKind::ExpectedRequirementField,
            span: Span::new(element.span.start, self.source.len()),
        })
    }

    fn parse_c4_body(&mut self, header: C4Header) -> Result<C4Ast, ParseError> {
        let span_start = header.span.start;
        let mut ast = C4Ast {
            header,
            title: None,
            statements: Vec::new(),
            elements: Vec::new(),
            relationships: Vec::new(),
            boundaries: Vec::new(),
            span: Span::new(span_start, self.source.len()),
        };
        let mut parents = Vec::<Spanned<String>>::new();

        while let Some(line) = self.current_trimmed_line() {
            if line.text == "}" {
                parents.pop();
                self.cursor = line.line.next;
                continue;
            }
            let (statement_text, opens_block) = if line.text.ends_with('{') {
                let end = line.end.saturating_sub(1);
                (&self.source[line.start..end], true)
            } else {
                (line.text, false)
            };
            let mut statement = shift_c4_statement(
                Parser::parse_c4_statement(statement_text)
                    .map_err(|error| shift_error(error, line.start))?,
                line.start,
            );
            if let Some(parent) = parents.last().cloned() {
                attach_c4_parent(&mut statement, parent);
            }
            if opens_block && let Some(alias) = c4_statement_alias(&statement) {
                parents.push(alias);
            }
            push_c4_statement(&mut ast, statement);
            self.cursor = line.line.next;
        }

        Ok(ast)
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

fn push_sequence_box_participant(
    ast: &mut SequenceAst,
    box_stack: &[(usize, usize)],
    participant: Spanned<String>,
) {
    for (box_index, statement_index) in box_stack {
        ast.boxes[*box_index].participants.push(participant.clone());
        if let Some(SequenceStatement::Box(sequence_box)) = ast.statements.get_mut(*statement_index)
        {
            sequence_box.participants.push(participant.clone());
        }
    }
}

fn parse_flow_document_statements(
    statement: &str,
    offset: usize,
) -> Result<Vec<FlowStatement>, ParseError> {
    if let Ok(directive) = Parser::parse_mermaid_directive(statement) {
        let directive = shift_directive(directive, offset);
        reject_unsupported_flowchart_config_directive(&directive)?;
        return Ok(vec![FlowStatement::Directive(directive)]);
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
    match Parser::parse_flow_node(statement) {
        Ok(node) => return Ok(vec![FlowStatement::Node(shift_node(node, offset))]),
        Err(error) if error.kind == ParseErrorKind::ReservedFlowNodeLabel => {
            return Err(ParseError {
                kind: error.kind,
                span: shift_span(error.span, offset),
            });
        }
        Err(_) => {}
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

fn push_gantt_statement(ast: &mut GanttAst, statement: GanttStatement) {
    match &statement {
        GanttStatement::Title(title) => ast.title = Some(title.clone()),
        GanttStatement::DateFormat(format) => ast.date_format = Some(format.clone()),
        GanttStatement::AxisFormat(format) => ast.axis_format = Some(format.clone()),
        GanttStatement::Task(task) => ast.tasks.push((**task).clone()),
        GanttStatement::Section(_)
        | GanttStatement::Config(_)
        | GanttStatement::Comment(_)
        | GanttStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_pie_statement(ast: &mut PieAst, statement: PieStatement) {
    match &statement {
        PieStatement::Title(title) => ast.title = Some(title.clone()),
        PieStatement::Slice(slice) => ast.slices.push(slice.clone()),
        PieStatement::Comment(_) | PieStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_quadrant_statement(ast: &mut QuadrantAst, statement: QuadrantStatement) {
    match &statement {
        QuadrantStatement::Title(title) => ast.title = Some(title.clone()),
        QuadrantStatement::Axis(axis) => match axis.kind.value {
            QuadrantAxisKind::X => ast.x_axis = Some(axis.clone()),
            QuadrantAxisKind::Y => ast.y_axis = Some(axis.clone()),
        },
        QuadrantStatement::Quadrant(section) => {
            if let Some(existing) = ast
                .quadrants
                .iter_mut()
                .find(|existing| existing.index.value == section.index.value)
            {
                *existing = section.clone();
            } else {
                ast.quadrants.push(section.clone());
            }
        }
        QuadrantStatement::Point(point) => ast.points.push((**point).clone()),
        QuadrantStatement::ClassDef(class_def) => ast.classes.push(class_def.clone()),
        QuadrantStatement::ClassApply(_)
        | QuadrantStatement::Comment(_)
        | QuadrantStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_zenuml_statement(ast: &mut ZenUmlAst, statement: ZenUmlStatement) {
    match &statement {
        ZenUmlStatement::Title(title) => ast.title = Some(title.clone()),
        ZenUmlStatement::Participant(participant) => {
            ensure_zenuml_participant(ast, participant.clone());
        }
        ZenUmlStatement::Message(message) => {
            if let Some(from) = &message.from {
                ensure_zenuml_participant(
                    ast,
                    ZenUmlParticipant {
                        id: from.clone(),
                        label: None,
                        annotator: None,
                        span: from.span,
                    },
                );
            }
            if message.to.value != "return" {
                ensure_zenuml_participant(
                    ast,
                    ZenUmlParticipant {
                        id: message.to.clone(),
                        label: None,
                        annotator: None,
                        span: message.to.span,
                    },
                );
            }
            ast.messages.push((**message).clone());
        }
        ZenUmlStatement::Fragment(fragment) => ast.fragments.push(fragment.clone()),
        ZenUmlStatement::BlockEnd(_)
        | ZenUmlStatement::Comment(_)
        | ZenUmlStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_sankey_statement(ast: &mut SankeyAst, statement: SankeyStatement) {
    match &statement {
        SankeyStatement::Link(link) => ast.links.push((**link).clone()),
        SankeyStatement::Comment(_) | SankeyStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_xy_chart_statement(ast: &mut XyChartAst, statement: XyChartStatement) {
    match &statement {
        XyChartStatement::Title(title) => ast.title = Some(title.clone()),
        XyChartStatement::Axis(axis) => match axis.kind.value {
            XyChartAxisKind::X => ast.x_axis = Some(axis.clone()),
            XyChartAxisKind::Y => ast.y_axis = Some(axis.clone()),
        },
        XyChartStatement::Series(series) => ast.series.push(series.clone()),
        XyChartStatement::Comment(_) | XyChartStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_block_statement(ast: &mut BlockDiagramAst, statement: BlockStatement) {
    match &statement {
        BlockStatement::Node(node) => upsert_block_node(&mut ast.blocks, (**node).clone()),
        BlockStatement::Container(container) => {
            for statement in &container.statements {
                push_block_statement(ast, statement.clone());
            }
        }
        BlockStatement::Edge(edge) => {
            upsert_block_node(&mut ast.blocks, edge.from_node.clone());
            upsert_block_node(&mut ast.blocks, edge.to_node.clone());
            ast.edges.push((**edge).clone());
        }
        BlockStatement::ClassDef(class_def) => ast.classes.push(class_def.clone()),
        BlockStatement::Style(style) => ast.styles.push(style.clone()),
        BlockStatement::Columns(_)
        | BlockStatement::Space(_)
        | BlockStatement::ClassApply(_)
        | BlockStatement::Comment(_)
        | BlockStatement::Directive(_) => {}
    }
}

fn push_packet_statement(ast: &mut PacketAst, statement: PacketStatement) {
    match &statement {
        PacketStatement::Title(title) => ast.title = Some(title.clone()),
        PacketStatement::Field(field) => ast.fields.push((**field).clone()),
        PacketStatement::Comment(_) | PacketStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_architecture_statement(ast: &mut ArchitectureAst, statement: ArchitectureStatement) {
    match &statement {
        ArchitectureStatement::Group(group) => ast.groups.push((**group).clone()),
        ArchitectureStatement::Service(service) => ast.services.push((**service).clone()),
        ArchitectureStatement::Junction(junction) => ast.junctions.push((**junction).clone()),
        ArchitectureStatement::Edge(edge) => ast.edges.push((**edge).clone()),
        ArchitectureStatement::Alignment(alignment) => ast.alignments.push((**alignment).clone()),
        ArchitectureStatement::Comment(_) | ArchitectureStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_radar_statement(ast: &mut RadarAst, statement: RadarStatement) {
    match &statement {
        RadarStatement::Title(title) => ast.title = Some(title.clone()),
        RadarStatement::Axis(axis) => ast.axes.push((**axis).clone()),
        RadarStatement::Curve(curve) => ast.curves.push((**curve).clone()),
        RadarStatement::Option(option) => ast.options.push((**option).clone()),
        RadarStatement::Comment(_) | RadarStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_event_modeling_statement(ast: &mut EventModelingAst, statement: EventModelingStatement) {
    match &statement {
        EventModelingStatement::TimeFrame(frame) => ast.timeframes.push((**frame).clone()),
        EventModelingStatement::DataBlock(block) => ast.data_blocks.push((**block).clone()),
        EventModelingStatement::Comment(_) | EventModelingStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn attach_venn_text(ast: &mut VennAst, owner: &VennTextOwner, text: VennText) {
    match owner {
        VennTextOwner::Set(id) => {
            if let Some(set) = ast.sets.iter_mut().rev().find(|set| set.id.value == *id) {
                set.texts.push(text);
            }
        }
        VennTextOwner::Union(members) => {
            if let Some(union) = ast
                .unions
                .iter_mut()
                .rev()
                .find(|union| venn_members_match(&union.members, members))
            {
                union.texts.push(text);
            }
        }
    }
}

fn venn_members_match(actual: &[Spanned<String>], expected: &[String]) -> bool {
    actual.len() == expected.len()
        && actual
            .iter()
            .zip(expected)
            .all(|(actual, expected)| actual.value == *expected)
}

fn upsert_block_node(nodes: &mut Vec<BlockNode>, node: BlockNode) {
    if let Some(existing) = nodes
        .iter_mut()
        .find(|existing| existing.id.value == node.id.value)
    {
        if node.label.is_some() {
            existing.label = node.label;
        }
        existing.shape = node.shape;
        if node.width.span.start != node.width.span.end {
            existing.width = node.width;
        }
        existing.span = node.span;
        return;
    }
    nodes.push(node);
}

fn ensure_zenuml_participant(ast: &mut ZenUmlAst, participant: ZenUmlParticipant) {
    if let Some(existing) = ast
        .participants
        .iter_mut()
        .find(|existing| existing.id.value == participant.id.value)
    {
        if participant.label.is_some() {
            *existing = participant;
        }
    } else {
        ast.participants.push(participant);
    }
}

fn push_journey_statement(ast: &mut JourneyAst, statement: JourneyStatement) {
    match &statement {
        JourneyStatement::Title(title) => ast.title = Some(title.clone()),
        JourneyStatement::Task(task) => ast.tasks.push((**task).clone()),
        JourneyStatement::Section(_)
        | JourneyStatement::Comment(_)
        | JourneyStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_gitgraph_statement(ast: &mut GitGraphAst, statement: GitGraphStatement) {
    match &statement {
        GitGraphStatement::Commit(commit) => ast.commits.push((**commit).clone()),
        GitGraphStatement::Branch(branch) => ast.branches.push((**branch).clone()),
        GitGraphStatement::Merge(merge) => ast.merges.push((**merge).clone()),
        GitGraphStatement::CherryPick(cherry_pick) => {
            ast.cherry_picks.push((**cherry_pick).clone());
        }
        GitGraphStatement::Checkout(_)
        | GitGraphStatement::Comment(_)
        | GitGraphStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn push_timeline_statement(
    ast: &mut TimelineAst,
    statement: TimelineStatement,
) -> Result<(), ParseError> {
    match &statement {
        TimelineStatement::Title(title) => ast.title = Some(title.clone()),
        TimelineStatement::Period(period) => ast.periods.push((**period).clone()),
        TimelineStatement::Event(event) => {
            let Some(period) = ast.periods.last_mut() else {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedTimelinePeriod,
                    span: event.span,
                });
            };
            period.events.push(event.clone());
        }
        TimelineStatement::Section(_)
        | TimelineStatement::Comment(_)
        | TimelineStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
    Ok(())
}

fn push_requirement_statement(ast: &mut RequirementAst, statement: RequirementStatement) {
    match &statement {
        RequirementStatement::Requirement(node) => {
            merge_requirement_node(&mut ast.requirements, node);
        }
        RequirementStatement::Element(element) => {
            merge_requirement_element(&mut ast.elements, element);
        }
        RequirementStatement::Relationship(relationship) => {
            ensure_requirement_endpoint(ast, &relationship.from);
            ensure_requirement_endpoint(ast, &relationship.to);
            ast.relationships.push((**relationship).clone());
        }
        RequirementStatement::Direction(direction) => ast.direction = Some(*direction),
        RequirementStatement::Style(style) => ast.styles.push(style.clone()),
        RequirementStatement::ClassDef(class_def) => ast.classes.push(class_def.clone()),
        RequirementStatement::ClassApply(_)
        | RequirementStatement::Comment(_)
        | RequirementStatement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn merge_requirement_node(requirements: &mut Vec<RequirementNode>, node: &RequirementNode) {
    if let Some(existing) = requirements
        .iter_mut()
        .find(|value| value.name.value == node.name.value)
    {
        existing.kind = node.kind;
        existing.requirement_id = node
            .requirement_id
            .clone()
            .or(existing.requirement_id.clone());
        existing.text = node.text.clone().or(existing.text.clone());
        existing.risk = node.risk.or(existing.risk);
        existing.verify_method = node.verify_method.or(existing.verify_method);
        existing.classes.extend(node.classes.clone());
        existing.span = Span::new(existing.span.start.min(node.span.start), node.span.end);
        return;
    }
    requirements.push(node.clone());
}

fn merge_requirement_element(elements: &mut Vec<RequirementElement>, element: &RequirementElement) {
    if let Some(existing) = elements
        .iter_mut()
        .find(|value| value.name.value == element.name.value)
    {
        existing.ty = element.ty.clone().or(existing.ty.clone());
        existing.doc_ref = element.doc_ref.clone().or(existing.doc_ref.clone());
        existing.classes.extend(element.classes.clone());
        existing.span = Span::new(
            existing.span.start.min(element.span.start),
            element.span.end,
        );
        return;
    }
    elements.push(element.clone());
}

fn ensure_requirement_endpoint(ast: &mut RequirementAst, id: &Spanned<String>) {
    if ast
        .requirements
        .iter()
        .any(|node| node.name.value == id.value)
        || ast
            .elements
            .iter()
            .any(|element| element.name.value == id.value)
    {
        return;
    }
    ast.elements.push(RequirementElement {
        name: id.clone(),
        ty: None,
        doc_ref: None,
        classes: Vec::new(),
        span: id.span,
    });
}

fn push_c4_statement(ast: &mut C4Ast, statement: C4Statement) {
    match &statement {
        C4Statement::Title(title) => ast.title = Some(title.clone()),
        C4Statement::Element(element) => merge_c4_element(&mut ast.elements, element),
        C4Statement::Relationship(relationship) => {
            ensure_c4_element(&mut ast.elements, &relationship.from);
            ensure_c4_element(&mut ast.elements, &relationship.to);
            ast.relationships.push((**relationship).clone());
        }
        C4Statement::Boundary(boundary) => ast.boundaries.push((**boundary).clone()),
        C4Statement::Style(_)
        | C4Statement::Layout(_)
        | C4Statement::Comment(_)
        | C4Statement::Directive(_) => {}
    }
    ast.statements.push(statement);
}

fn merge_c4_element(elements: &mut Vec<C4Element>, element: &C4Element) {
    if let Some(existing) = elements
        .iter_mut()
        .find(|value| value.alias.value == element.alias.value)
    {
        *existing = element.clone();
        return;
    }
    elements.push(element.clone());
}

fn ensure_c4_element(elements: &mut Vec<C4Element>, alias: &Spanned<String>) {
    if elements
        .iter()
        .any(|element| element.alias.value == alias.value)
    {
        return;
    }
    elements.push(C4Element {
        alias: alias.clone(),
        label: Label {
            text: alias.value.clone(),
            kind: LabelKind::Plain,
            span: alias.span,
        },
        kind: Spanned::new(C4ElementKind::Component, alias.span),
        technology: None,
        description: None,
        parent: None,
        external: false,
        span: alias.span,
    });
}

fn attach_c4_parent(statement: &mut C4Statement, parent: Spanned<String>) {
    match statement {
        C4Statement::Element(element) => {
            if element.parent.is_none() {
                element.parent = Some(parent);
            }
        }
        C4Statement::Boundary(boundary) => {
            if boundary.parent.is_none() {
                boundary.parent = Some(parent);
            }
        }
        C4Statement::Title(_)
        | C4Statement::Relationship(_)
        | C4Statement::Style(_)
        | C4Statement::Layout(_)
        | C4Statement::Comment(_)
        | C4Statement::Directive(_) => {}
    }
}

fn c4_statement_alias(statement: &C4Statement) -> Option<Spanned<String>> {
    match statement {
        C4Statement::Element(element) => Some(element.alias.clone()),
        C4Statement::Boundary(boundary) => Some(boundary.alias.clone()),
        C4Statement::Title(_)
        | C4Statement::Relationship(_)
        | C4Statement::Style(_)
        | C4Statement::Layout(_)
        | C4Statement::Comment(_)
        | C4Statement::Directive(_) => None,
    }
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
        if has_keyword(self.source, start, "create") {
            return self.parse_create(start, end);
        }
        if has_keyword(self.source, start, "destroy") {
            return self.parse_destroy(start, end);
        }
        if has_exact_keyword(self.source, start, end, "box") {
            return self.parse_box(start, end);
        }
        if has_exact_keyword(self.source, start, end, "autonumber") {
            return self.parse_auto_number(start, end);
        }
        if has_keyword(self.source, start, "activate") {
            return self.parse_activation(start, end, "activate", true);
        }
        if has_keyword(self.source, start, "deactivate") {
            return self.parse_activation(start, end, "deactivate", false);
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

    fn parse_create(&self, start: usize, end: usize) -> Result<SequenceStatement, ParseError> {
        let rest_start = start + "create".len();
        let Some((trim_start, trim_end)) = trim_ascii_range(&self.source[rest_start..end]) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedSequenceParticipant,
                span: Span::new(rest_start, end),
            });
        };
        let participant_start = rest_start + trim_start;
        let participant_end = rest_start + trim_end;
        let statement = if has_keyword(self.source, participant_start, "participant") {
            self.parse_participant(
                participant_start,
                participant_end,
                "participant",
                SequenceParticipantKind::Participant,
            )?
        } else if has_keyword(self.source, participant_start, "actor") {
            self.parse_participant(
                participant_start,
                participant_end,
                "actor",
                SequenceParticipantKind::Actor,
            )?
        } else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedSequenceParticipant,
                span: Span::new(participant_start, participant_end),
            });
        };
        let SequenceStatement::Participant(participant) = statement else {
            unreachable!("parse_participant returns participant statement");
        };
        Ok(SequenceStatement::Create(Box::new(SequenceCreate {
            participant: *participant,
            span: Span::new(start, end),
        })))
    }

    fn parse_destroy(&self, start: usize, end: usize) -> Result<SequenceStatement, ParseError> {
        let participant = parse_single_identifier(
            self.source,
            start + "destroy".len(),
            end,
            ParseErrorKind::ExpectedSequenceParticipant,
        )?;
        Ok(SequenceStatement::Destroy(Box::new(SequenceDestroy {
            participant,
            span: Span::new(start, end),
        })))
    }

    fn parse_box(&self, start: usize, end: usize) -> Result<SequenceStatement, ParseError> {
        Ok(SequenceStatement::Box(Box::new(SequenceBox {
            label: label_from_trimmed(self.source, start + "box".len(), end),
            participants: Vec::new(),
            span: Span::new(start, end),
        })))
    }

    fn parse_auto_number(&self, start: usize, end: usize) -> Result<SequenceStatement, ParseError> {
        let values = parse_sequence_number_values(self.source, start + "autonumber".len(), end)?;
        Ok(SequenceStatement::AutoNumber(SequenceAutoNumber {
            start: values.first().cloned(),
            step: values.get(1).cloned(),
            span: Span::new(start, end),
        }))
    }

    fn parse_activation(
        &self,
        start: usize,
        end: usize,
        keyword: &str,
        is_start: bool,
    ) -> Result<SequenceStatement, ParseError> {
        let participant = parse_single_identifier(
            self.source,
            start + keyword.len(),
            end,
            ParseErrorKind::ExpectedSequenceParticipant,
        )?;
        if is_start {
            Ok(SequenceStatement::ActivationStart(participant))
        } else {
            Ok(SequenceStatement::ActivationEnd(participant))
        }
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
            ("critical", SequenceControlKind::Critical),
            ("break", SequenceControlKind::Break),
            ("rect", SequenceControlKind::Rect),
        ];
        for (keyword, kind) in controls {
            if !has_exact_keyword(self.source, start, end, keyword) {
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
        let (activation, to_start) = match self.source.as_bytes().get(message_start) {
            Some(b'+') => (
                Some(Spanned::new(
                    SequenceActivation::Start,
                    Span::new(message_start, message_start + 1),
                )),
                message_start + 1,
            ),
            Some(b'-') => (
                Some(Spanned::new(
                    SequenceActivation::End,
                    Span::new(message_start, message_start + 1),
                )),
                message_start + 1,
            ),
            _ => (None, message_start),
        };
        let to_end = message_start + colon;
        let to = parse_single_identifier(
            self.source,
            to_start,
            to_end,
            ParseErrorKind::ExpectedSequenceMessage,
        )?;
        let label = label_from_trimmed(self.source, to_end + 1, end);
        Ok(Some(SequenceMessage {
            from,
            to,
            arrow,
            activation,
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
        let (from, start_cardinality) = parse_class_source_endpoint(
            self.source,
            start,
            operator_start,
            ParseErrorKind::ExpectedClassRelationship,
        )?;
        let label_start = self.source[operator_end..end]
            .find(':')
            .map(|offset| operator_end + offset);
        let to_end = label_start.unwrap_or(end);
        let (to, end_cardinality) = parse_class_target_endpoint(
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
            start_cardinality,
            end_cardinality,
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

struct GanttHeaderParser<'source> {
    source: &'source str,
}

impl<'source> GanttHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<GanttHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedGanttHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "gantt" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedGanttHeader,
                span: Span::new(start, end),
            });
        }
        Ok(GanttHeader {
            span: Span::new(start, end),
        })
    }
}

struct GanttStatementParser<'source> {
    source: &'source str,
}

impl<'source> GanttStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<GanttStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownGanttStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(GanttStatement::Directive(shift_directive(directive, start)));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(GanttStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "title") {
            let label =
                label_from_trimmed(self.source, start + "title".len(), end).ok_or(ParseError {
                    kind: ParseErrorKind::UnknownGanttStatement,
                    span: Span::new(start, end),
                })?;
            return Ok(GanttStatement::Title(label));
        }
        if has_keyword(self.source, start, "dateFormat") {
            return Ok(GanttStatement::DateFormat(parse_gantt_value(
                self.source,
                start,
                end,
                "dateFormat",
            )?));
        }
        if has_keyword(self.source, start, "axisFormat") {
            return Ok(GanttStatement::AxisFormat(parse_gantt_value(
                self.source,
                start,
                end,
                "axisFormat",
            )?));
        }
        if has_keyword(self.source, start, "section") {
            let label = label_from_trimmed(self.source, start + "section".len(), end).ok_or(
                ParseError {
                    kind: ParseErrorKind::UnknownGanttStatement,
                    span: Span::new(start, end),
                },
            )?;
            return Ok(GanttStatement::Section(label));
        }
        if let Some(config) = self.parse_config(start, end)? {
            return Ok(GanttStatement::Config(config));
        }
        if let Some(task) = self.parse_task(start, end)? {
            return Ok(GanttStatement::Task(Box::new(task)));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownGanttStatement,
            span: Span::new(start, end),
        })
    }

    fn parse_config(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<GanttConfigStatement>, ParseError> {
        let configs = [
            "excludes",
            "weekend",
            "tickInterval",
            "todayMarker",
            "weekday",
            "click",
        ];
        let Some(key) = configs
            .iter()
            .find(|key| has_keyword(self.source, start, key))
        else {
            return Ok(None);
        };
        let key_span = Span::new(start, start + key.len());
        let value = label_from_trimmed(self.source, key_span.end, end);
        Ok(Some(GanttConfigStatement {
            key: Spanned::new((*key).to_owned(), key_span),
            value,
            span: Span::new(start, end),
        }))
    }

    fn parse_task(&self, start: usize, end: usize) -> Result<Option<GanttTask>, ParseError> {
        let Some(colon) = self.source[start..end].find(':') else {
            return Ok(None);
        };
        let colon = start + colon;
        let title = label_from_trimmed(self.source, start, colon).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedGanttTask,
            span: Span::new(start, colon),
        })?;
        let mut metadata = parse_gantt_metadata(self.source, colon + 1, end)?;
        let tags = take_gantt_tags(&mut metadata);
        let id = if metadata.len() == 3 && is_identifier(&metadata[0].value) {
            Some(metadata.remove(0))
        } else {
            None
        };
        if metadata.is_empty() {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedGanttMetadata,
                span: Span::new(colon + 1, end),
            });
        }
        Ok(Some(GanttTask {
            title,
            section: None,
            tags,
            id,
            metadata,
            span: Span::new(start, end),
        }))
    }
}

struct PieHeaderParser<'source> {
    source: &'source str,
}

impl<'source> PieHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<PieHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedPieHeader,
                span: Span::new(0, 0),
            });
        };
        if !has_exact_keyword(self.source, start, end, "pie") {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedPieHeader,
                span: Span::new(start, end),
            });
        }
        let mut cursor = start + "pie".len();
        let mut show_data = false;
        let mut title = None;
        if let Some((trim_start, trim_end)) = trim_ascii_range(&self.source[cursor..end]) {
            cursor += trim_start;
            let rest_end = cursor + (trim_end - trim_start);
            if has_exact_keyword(self.source, cursor, rest_end, "showData") {
                show_data = true;
                cursor += "showData".len();
                if let Some((inner_start, inner_end)) = trim_ascii_range(&self.source[cursor..end])
                {
                    cursor += inner_start;
                    let inner_absolute_end = cursor + (inner_end - inner_start);
                    if has_exact_keyword(self.source, cursor, inner_absolute_end, "title") {
                        title = label_from_trimmed(self.source, cursor + "title".len(), end);
                    } else if inner_absolute_end != cursor {
                        return Err(ParseError {
                            kind: ParseErrorKind::ExpectedPieHeader,
                            span: Span::new(cursor, inner_absolute_end),
                        });
                    }
                }
            } else if has_exact_keyword(self.source, cursor, rest_end, "title") {
                title = label_from_trimmed(self.source, cursor + "title".len(), end);
            } else if rest_end != cursor {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedPieHeader,
                    span: Span::new(cursor, rest_end),
                });
            }
        }
        Ok(PieHeader {
            show_data,
            title,
            span: Span::new(start, end),
        })
    }
}

struct QuadrantHeaderParser<'source> {
    source: &'source str,
}

impl<'source> QuadrantHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<QuadrantHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedQuadrantHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "quadrantChart" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedQuadrantHeader,
                span: Span::new(start, end),
            });
        }
        Ok(QuadrantHeader {
            span: Span::new(start, end),
        })
    }
}

struct ZenUmlHeaderParser<'source> {
    source: &'source str,
}

impl<'source> ZenUmlHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<ZenUmlHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedZenUmlHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "zenuml" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedZenUmlHeader,
                span: Span::new(start, end),
            });
        }
        Ok(ZenUmlHeader {
            span: Span::new(start, end),
        })
    }
}

struct SankeyHeaderParser<'source> {
    source: &'source str,
}

impl<'source> SankeyHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<SankeyHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedSankeyHeader,
                span: Span::new(0, 0),
            });
        };
        if !matches!(&self.source[start..end], "sankey" | "sankey-beta") {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedSankeyHeader,
                span: Span::new(start, end),
            });
        }
        Ok(SankeyHeader {
            span: Span::new(start, end),
        })
    }
}

struct XyChartHeaderParser<'source> {
    source: &'source str,
}

impl<'source> XyChartHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<XyChartHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedXyChartHeader,
                span: Span::new(0, 0),
            });
        };
        let root_end = self.source[start..end]
            .find(|value: char| value.is_ascii_whitespace())
            .map_or(end, |offset| start + offset);
        if !matches!(&self.source[start..root_end], "xychart" | "xychart-beta") {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedXyChartHeader,
                span: Span::new(start, end),
            });
        }
        let orientation =
            if let Some((trim_start, trim_end)) = trim_ascii_range(&self.source[root_end..end]) {
                let orientation_start = root_end + trim_start;
                let orientation_end = root_end + trim_end;
                let orientation = match &self.source[orientation_start..orientation_end] {
                    "horizontal" => XyChartOrientation::Horizontal,
                    "vertical" => XyChartOrientation::Vertical,
                    _ => {
                        return Err(ParseError {
                            kind: ParseErrorKind::ExpectedXyChartHeader,
                            span: Span::new(orientation_start, orientation_end),
                        });
                    }
                };
                Some(Spanned::new(
                    orientation,
                    Span::new(orientation_start, orientation_end),
                ))
            } else {
                None
            };
        Ok(XyChartHeader {
            orientation,
            span: Span::new(start, end),
        })
    }
}

struct BlockHeaderParser<'source> {
    source: &'source str,
}

impl<'source> BlockHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<BlockDiagramHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedBlockHeader,
                span: Span::new(0, 0),
            });
        };
        let root_end = self.source[start..end]
            .find(|value: char| value.is_ascii_whitespace())
            .map_or(end, |offset| start + offset);
        if &self.source[start..root_end] != "block" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedBlockHeader,
                span: Span::new(start, end),
            });
        }
        let columns =
            if let Some((rest_start, rest_end)) = trim_ascii_range(&self.source[root_end..end]) {
                let rest_start = root_end + rest_start;
                let rest_end = root_end + rest_end;
                Some(parse_block_columns(self.source, rest_start, rest_end)?)
            } else {
                None
            };
        Ok(BlockDiagramHeader {
            columns,
            span: Span::new(start, end),
        })
    }
}

struct PacketHeaderParser<'source> {
    source: &'source str,
}

impl<'source> PacketHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<PacketHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedPacketHeader,
                span: Span::new(0, 0),
            });
        };
        if !matches!(&self.source[start..end], "packet" | "packet-beta") {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedPacketHeader,
                span: Span::new(start, end),
            });
        }
        Ok(PacketHeader {
            span: Span::new(start, end),
        })
    }
}

struct KanbanHeaderParser<'source> {
    source: &'source str,
}

impl<'source> KanbanHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<KanbanHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedKanbanHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "kanban" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedKanbanHeader,
                span: Span::new(start, end),
            });
        }
        Ok(KanbanHeader {
            span: Span::new(start, end),
        })
    }
}

struct ArchitectureHeaderParser<'source> {
    source: &'source str,
}

impl<'source> ArchitectureHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<ArchitectureHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedArchitectureHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "architecture-beta" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedArchitectureHeader,
                span: Span::new(start, end),
            });
        }
        Ok(ArchitectureHeader {
            span: Span::new(start, end),
        })
    }
}

struct RadarHeaderParser<'source> {
    source: &'source str,
}

impl<'source> RadarHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<RadarHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedRadarHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "radar-beta" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedRadarHeader,
                span: Span::new(start, end),
            });
        }
        Ok(RadarHeader {
            span: Span::new(start, end),
        })
    }
}

struct EventModelingHeaderParser<'source> {
    source: &'source str,
}

impl<'source> EventModelingHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<EventModelingHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedEventModelingHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "eventmodeling" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedEventModelingHeader,
                span: Span::new(start, end),
            });
        }
        Ok(EventModelingHeader {
            span: Span::new(start, end),
        })
    }
}

struct TreemapHeaderParser<'source> {
    source: &'source str,
}

impl<'source> TreemapHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<TreemapHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedTreemapHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "treemap-beta" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedTreemapHeader,
                span: Span::new(start, end),
            });
        }
        Ok(TreemapHeader {
            span: Span::new(start, end),
        })
    }
}

struct VennHeaderParser<'source> {
    source: &'source str,
}

impl<'source> VennHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<VennHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedVennHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "venn-beta" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedVennHeader,
                span: Span::new(start, end),
            });
        }
        Ok(VennHeader {
            span: Span::new(start, end),
        })
    }
}

struct IshikawaHeaderParser<'source> {
    source: &'source str,
}

impl<'source> IshikawaHeaderParser<'source> {
    const fn new(source: &'source str) -> Self {
        Self { source }
    }

    fn parse(&self) -> Result<IshikawaHeader, ParseError> {
        let (start, end) = trim_ascii_range(self.source).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedIshikawaHeader,
            span: Span::new(0, self.source.len()),
        })?;
        if &self.source[start..end] != "ishikawa-beta" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedIshikawaHeader,
                span: Span::new(start, end),
            });
        }
        Ok(IshikawaHeader {
            span: Span::new(start, end),
        })
    }
}

struct WardleyHeaderParser<'source> {
    source: &'source str,
}

impl<'source> WardleyHeaderParser<'source> {
    const fn new(source: &'source str) -> Self {
        Self { source }
    }

    fn parse(&self) -> Result<WardleyHeader, ParseError> {
        let (start, end) = trim_ascii_range(self.source).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedWardleyHeader,
            span: Span::new(0, self.source.len()),
        })?;
        if &self.source[start..end] != "wardley-beta" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedWardleyHeader,
                span: Span::new(start, end),
            });
        }
        Ok(WardleyHeader {
            span: Span::new(start, end),
        })
    }
}

struct MindmapHeaderParser<'source> {
    source: &'source str,
}

impl<'source> MindmapHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<MindmapHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedMindmapHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "mindmap" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedMindmapHeader,
                span: Span::new(start, end),
            });
        }
        Ok(MindmapHeader {
            span: Span::new(start, end),
        })
    }
}

struct JourneyHeaderParser<'source> {
    source: &'source str,
}

impl<'source> JourneyHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<JourneyHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedJourneyHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "journey" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedJourneyHeader,
                span: Span::new(start, end),
            });
        }
        Ok(JourneyHeader {
            span: Span::new(start, end),
        })
    }
}

struct PieStatementParser<'source> {
    source: &'source str,
}

impl<'source> PieStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<PieStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownPieStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(PieStatement::Directive(shift_directive(directive, start)));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(PieStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "title") {
            let label =
                label_from_trimmed(self.source, start + "title".len(), end).ok_or(ParseError {
                    kind: ParseErrorKind::UnknownPieStatement,
                    span: Span::new(start, end),
                })?;
            return Ok(PieStatement::Title(label));
        }
        if let Some(slice) = self.parse_slice(start, end)? {
            return Ok(PieStatement::Slice(slice));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownPieStatement,
            span: Span::new(start, end),
        })
    }

    fn parse_slice(&self, start: usize, end: usize) -> Result<Option<PieSlice>, ParseError> {
        let Some(colon) = self.source[start..end].find(':') else {
            return Ok(None);
        };
        let colon = start + colon;
        let label = label_from_trimmed(self.source, start, colon).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedPieSlice,
            span: Span::new(start, colon),
        })?;
        let (value_units, value_text) = parse_pie_value(self.source, colon + 1, end)?;
        Ok(Some(PieSlice {
            label,
            value_units,
            value_text,
            span: Span::new(start, end),
        }))
    }
}

struct QuadrantStatementParser<'source> {
    source: &'source str,
}

impl<'source> QuadrantStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<QuadrantStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownQuadrantStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(QuadrantStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(QuadrantStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "title") {
            let label =
                label_from_trimmed(self.source, start + "title".len(), end).ok_or(ParseError {
                    kind: ParseErrorKind::UnknownQuadrantStatement,
                    span: Span::new(start, end),
                })?;
            return Ok(QuadrantStatement::Title(label));
        }
        if has_keyword(self.source, start, "x-axis") {
            return Ok(QuadrantStatement::Axis(self.parse_axis(
                start,
                end,
                "x-axis",
                QuadrantAxisKind::X,
            )?));
        }
        if has_keyword(self.source, start, "y-axis") {
            return Ok(QuadrantStatement::Axis(self.parse_axis(
                start,
                end,
                "y-axis",
                QuadrantAxisKind::Y,
            )?));
        }
        if let Some(section) = self.parse_quadrant_section(start, end)? {
            return Ok(QuadrantStatement::Quadrant(section));
        }
        if let Ok(class_def) = Parser::parse_flow_class_def(trimmed) {
            return Ok(QuadrantStatement::ClassDef(shift_class_def(
                class_def, start,
            )));
        }
        if let Ok(class_apply) = Parser::parse_flow_class_apply(trimmed) {
            return Ok(QuadrantStatement::ClassApply(shift_class_apply(
                class_apply,
                start,
            )));
        }
        if let Some(point) = self.parse_point(start, end)? {
            return Ok(QuadrantStatement::Point(Box::new(point)));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownQuadrantStatement,
            span: Span::new(start, end),
        })
    }

    fn parse_axis(
        &self,
        start: usize,
        end: usize,
        keyword: &str,
        kind: QuadrantAxisKind,
    ) -> Result<QuadrantAxis, ParseError> {
        let rest_start = start + keyword.len();
        let Some(arrow) = self.source[rest_start..end].find("-->") else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedQuadrantAxis,
                span: Span::new(rest_start, end),
            });
        };
        let arrow = rest_start + arrow;
        let label_start = label_from_trimmed(self.source, rest_start, arrow).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedQuadrantAxis,
            span: Span::new(rest_start, arrow),
        })?;
        let label_end =
            label_from_trimmed(self.source, arrow + "-->".len(), end).ok_or(ParseError {
                kind: ParseErrorKind::ExpectedQuadrantAxis,
                span: Span::new(arrow + "-->".len(), end),
            })?;
        Ok(QuadrantAxis {
            kind: Spanned::new(kind, Span::new(start, start + keyword.len())),
            start: label_start,
            end: label_end,
            span: Span::new(start, end),
        })
    }

    fn parse_quadrant_section(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<QuadrantSection>, ParseError> {
        let prefix = "quadrant-";
        if !self.source[start..end].starts_with(prefix) {
            return Ok(None);
        }
        let index_start = start + prefix.len();
        let Some(index_byte) = self.source.as_bytes().get(index_start).copied() else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownQuadrantStatement,
                span: Span::new(start, end),
            });
        };
        let value = match index_byte {
            b'1'..=b'4' => index_byte - b'0',
            _ => {
                return Err(ParseError {
                    kind: ParseErrorKind::UnknownQuadrantStatement,
                    span: Span::new(start, end),
                });
            }
        };
        let label_start = index_start + 1;
        if !self
            .source
            .as_bytes()
            .get(label_start)
            .is_some_and(u8::is_ascii_whitespace)
        {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownQuadrantStatement,
                span: Span::new(start, end),
            });
        }
        let label = label_from_trimmed(self.source, label_start, end).ok_or(ParseError {
            kind: ParseErrorKind::UnknownQuadrantStatement,
            span: Span::new(label_start, end),
        })?;
        Ok(Some(QuadrantSection {
            index: Spanned::new(value, Span::new(index_start, index_start + 1)),
            label,
            span: Span::new(start, end),
        }))
    }

    fn parse_point(&self, start: usize, end: usize) -> Result<Option<QuadrantPoint>, ParseError> {
        let Some(colon_offset) = self.source[start..end].find(':') else {
            return Ok(None);
        };
        let colon = start + colon_offset;
        let label = label_from_trimmed(self.source, start, colon).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedQuadrantPoint,
            span: Span::new(start, colon),
        })?;
        let value_start = colon + 1;
        let Some((trim_start, trim_end)) = trim_ascii_range(&self.source[value_start..end]) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedQuadrantPoint,
                span: Span::new(value_start, end),
            });
        };
        let absolute_start = value_start + trim_start;
        let absolute_end = value_start + trim_end;
        let bytes = self.source.as_bytes();
        if bytes.get(absolute_start) != Some(&b'[')
            || bytes.get(absolute_end.saturating_sub(1)) != Some(&b']')
        {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedQuadrantPoint,
                span: Span::new(absolute_start, absolute_end),
            });
        }
        let inner_start = absolute_start + 1;
        let inner_end = absolute_end - 1;
        let Some(comma) = self.source[inner_start..inner_end].find(',') else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedQuadrantPoint,
                span: Span::new(inner_start, inner_end),
            });
        };
        let comma = inner_start + comma;
        Ok(Some(QuadrantPoint {
            label,
            x: parse_quadrant_value(self.source, inner_start, comma)?,
            y: parse_quadrant_value(self.source, comma + 1, inner_end)?,
            span: Span::new(start, end),
        }))
    }
}

struct ZenUmlStatementParser<'source> {
    source: &'source str,
    depth: u16,
}

impl<'source> ZenUmlStatementParser<'source> {
    fn new(source: &'source str, depth: u16) -> Self {
        Self {
            source: first_line(source),
            depth,
        }
    }

    fn parse(&self) -> Result<ZenUmlStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownZenUmlStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(ZenUmlStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Some(comment) = self.parse_comment(start, end) {
            return Ok(ZenUmlStatement::Comment(comment));
        }
        if has_keyword(self.source, start, "title") {
            let label =
                label_from_trimmed(self.source, start + "title".len(), end).ok_or(ParseError {
                    kind: ParseErrorKind::UnknownZenUmlStatement,
                    span: Span::new(start, end),
                })?;
            return Ok(ZenUmlStatement::Title(label));
        }
        if let Some(fragment) = self.parse_fragment(start, end)? {
            return Ok(ZenUmlStatement::Fragment(fragment));
        }
        if let Some(message) = self.parse_message(start, end)? {
            return Ok(ZenUmlStatement::Message(Box::new(message)));
        }
        if let Some(participant) = self.parse_participant(start, end)? {
            return Ok(ZenUmlStatement::Participant(participant));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownZenUmlStatement,
            span: Span::new(start, end),
        })
    }

    fn parse_comment(&self, start: usize, end: usize) -> Option<MermaidComment> {
        if self.source[start..end].starts_with("//") {
            return Some(MermaidComment {
                text: self.source[start + 2..end].trim().to_owned(),
                span: Span::new(start, end),
            });
        }
        Parser::parse_mermaid_comment(&self.source[start..end])
            .ok()
            .map(|comment| shift_comment(comment, start))
    }

    fn parse_fragment(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<ZenUmlFragment>, ParseError> {
        let Some((keyword, kind)) = zenuml_fragment_keyword(&self.source[start..end]) else {
            return Ok(None);
        };
        let label = label_from_trimmed(self.source, start + keyword.len(), end);
        Ok(Some(ZenUmlFragment {
            kind: Spanned::new(kind, Span::new(start, start + keyword.len())),
            label,
            depth: self.depth,
            span: Span::new(start, end),
        }))
    }

    fn parse_message(&self, start: usize, end: usize) -> Result<Option<ZenUmlMessage>, ParseError> {
        if has_keyword(self.source, start, "return") {
            let label = label_from_trimmed(self.source, start + "return".len(), end);
            return Ok(Some(ZenUmlMessage {
                from: None,
                to: Spanned::new(
                    "return".to_owned(),
                    Span::new(start, start + "return".len()),
                ),
                label,
                kind: Spanned::new(
                    ZenUmlMessageKind::Reply,
                    Span::new(start, start + "return".len()),
                ),
                depth: self.depth,
                span: Span::new(start, end),
            }));
        }
        if has_keyword(self.source, start, "new") {
            return Ok(Some(self.parse_create_message(start, end)?));
        }
        let mut message_start = start;
        let mut kind_override = None;
        if self.source[start..end].starts_with("@return") {
            message_start = start + "@return".len();
            kind_override = Some(ZenUmlMessageKind::Reply);
        }
        if let Some(message) = self.parse_arrow_message(message_start, end, kind_override)? {
            return Ok(Some(message.with_span_start(start)));
        }
        if let Some(message) = self.parse_call_message(start, end)? {
            return Ok(Some(message));
        }
        Ok(None)
    }

    fn parse_create_message(&self, start: usize, end: usize) -> Result<ZenUmlMessage, ParseError> {
        let target_start = start + "new".len();
        let target = parse_zenuml_target(self.source, target_start, end)?;
        Ok(ZenUmlMessage {
            from: None,
            label: label_from_trimmed(self.source, start, end),
            kind: Spanned::new(
                ZenUmlMessageKind::Create,
                Span::new(start, start + "new".len()),
            ),
            depth: self.depth,
            span: Span::new(start, end),
            to: target,
        })
    }

    fn parse_arrow_message(
        &self,
        start: usize,
        end: usize,
        kind_override: Option<ZenUmlMessageKind>,
    ) -> Result<Option<ZenUmlMessage>, ParseError> {
        let Some(arrow_offset) = self.source[start..end].find("->") else {
            return Ok(None);
        };
        let arrow = start + arrow_offset;
        let from = parse_zenuml_target(self.source, start, arrow)?;
        let rhs_start = arrow + "->".len();
        let (to_end, label) = if let Some(colon) = self.source[rhs_start..end].find(':') {
            let colon = rhs_start + colon;
            (
                colon,
                label_from_trimmed(self.source, colon + 1, end)
                    .or_else(|| label_from_trimmed(self.source, rhs_start, end)),
            )
        } else {
            let target_end = zenuml_target_end(self.source, rhs_start, end);
            (
                target_end,
                zenuml_method_label(self.source, rhs_start, end)
                    .or_else(|| label_from_trimmed(self.source, target_end, end)),
            )
        };
        let to = parse_zenuml_target(self.source, rhs_start, to_end)?;
        Ok(Some(ZenUmlMessage {
            from: Some(from),
            to,
            label,
            kind: Spanned::new(
                kind_override.unwrap_or(ZenUmlMessageKind::Async),
                Span::new(arrow, arrow + "->".len()),
            ),
            depth: self.depth,
            span: Span::new(start, end),
        }))
    }

    fn parse_call_message(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<ZenUmlMessage>, ParseError> {
        let expression_start = self.source[start..end]
            .find('=')
            .map_or(start, |offset| start + offset + 1);
        let Some(dot_offset) = self.source[expression_start..end].find('.') else {
            return Ok(None);
        };
        let dot = expression_start + dot_offset;
        let to = parse_zenuml_target(self.source, expression_start, dot)?;
        let label = label_from_trimmed(self.source, dot + 1, end)
            .or_else(|| label_from_trimmed(self.source, expression_start, end));
        Ok(Some(ZenUmlMessage {
            from: None,
            to,
            label,
            kind: Spanned::new(ZenUmlMessageKind::Sync, Span::new(dot, dot + 1)),
            depth: self.depth,
            span: Span::new(start, end),
        }))
    }

    fn parse_participant(
        &self,
        start: usize,
        end: usize,
    ) -> Result<Option<ZenUmlParticipant>, ParseError> {
        let mut participant_start = start;
        let mut annotator = None;
        if has_keyword(self.source, start, "participant") {
            participant_start = start + "participant".len();
        } else if self.source[start..end].starts_with('@') {
            let annotator_end = self.source[start..end]
                .find(|value: char| value.is_ascii_whitespace())
                .map_or(end, |offset| start + offset);
            annotator = Some(Spanned::new(
                self.source[start + 1..annotator_end].to_owned(),
                Span::new(start + 1, annotator_end),
            ));
            participant_start = annotator_end;
        }
        let Some((trim_start, trim_end)) = trim_ascii_range(&self.source[participant_start..end])
        else {
            return Ok(None);
        };
        let id_start = participant_start + trim_start;
        let rest_end = participant_start + trim_end;
        if !zenuml_decl_like(&self.source[id_start..rest_end], annotator.is_some()) {
            return Ok(None);
        }
        Ok(Some(parse_zenuml_participant_decl(
            self.source,
            id_start,
            rest_end,
            annotator,
        )?))
    }
}

trait ZenUmlMessageSpan {
    fn with_span_start(self, start: usize) -> Self;
}

impl ZenUmlMessageSpan for ZenUmlMessage {
    fn with_span_start(mut self, start: usize) -> Self {
        self.span = Span::new(start, self.span.end);
        self
    }
}

struct SankeyStatementParser<'source> {
    source: &'source str,
}

impl<'source> SankeyStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<SankeyStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownSankeyStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(SankeyStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(SankeyStatement::Comment(shift_comment(comment, start)));
        }
        Ok(SankeyStatement::Link(Box::new(parse_sankey_link(
            self.source,
            start,
            end,
        )?)))
    }
}

struct XyChartStatementParser<'source> {
    source: &'source str,
}

impl<'source> XyChartStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<XyChartStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownXyChartStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(XyChartStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(XyChartStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "title") {
            let label =
                label_from_trimmed(self.source, start + "title".len(), end).ok_or(ParseError {
                    kind: ParseErrorKind::UnknownXyChartStatement,
                    span: Span::new(start, end),
                })?;
            return Ok(XyChartStatement::Title(label));
        }
        if has_keyword(self.source, start, "x-axis") {
            return Ok(XyChartStatement::Axis(parse_xy_chart_axis(
                self.source,
                start,
                end,
                "x-axis",
                XyChartAxisKind::X,
            )?));
        }
        if has_keyword(self.source, start, "y-axis") {
            return Ok(XyChartStatement::Axis(parse_xy_chart_axis(
                self.source,
                start,
                end,
                "y-axis",
                XyChartAxisKind::Y,
            )?));
        }
        if has_keyword(self.source, start, "line") {
            return Ok(XyChartStatement::Series(parse_xy_chart_series(
                self.source,
                start,
                end,
                "line",
                XyChartSeriesKind::Line,
            )?));
        }
        if has_keyword(self.source, start, "bar") {
            return Ok(XyChartStatement::Series(parse_xy_chart_series(
                self.source,
                start,
                end,
                "bar",
                XyChartSeriesKind::Bar,
            )?));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownXyChartStatement,
            span: Span::new(start, end),
        })
    }
}

struct PacketStatementParser<'source> {
    source: &'source str,
    next_bit: u32,
}

impl<'source> PacketStatementParser<'source> {
    fn new(source: &'source str, next_bit: u32) -> Self {
        Self {
            source: first_line(source),
            next_bit,
        }
    }

    fn parse(&self) -> Result<PacketStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownPacketStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(PacketStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(PacketStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "title") {
            let label =
                label_from_trimmed(self.source, start + "title".len(), end).ok_or(ParseError {
                    kind: ParseErrorKind::UnknownPacketStatement,
                    span: Span::new(start, end),
                })?;
            return Ok(PacketStatement::Title(label));
        }
        Ok(PacketStatement::Field(Box::new(parse_packet_field(
            self.source,
            start,
            end,
            self.next_bit,
        )?)))
    }
}

fn parse_block_line_statements(source: &str) -> Result<Vec<BlockStatement>, ParseError> {
    let Some((start, end)) = trimmed_statement_bounds(source) else {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownBlockStatement,
            span: Span::new(0, 0),
        });
    };
    let trimmed = &source[start..end];
    if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
        return Ok(vec![BlockStatement::Directive(shift_directive(
            directive, start,
        ))]);
    }
    if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
        return Ok(vec![BlockStatement::Comment(shift_comment(comment, start))]);
    }
    if has_keyword(source, start, "columns") {
        return Ok(vec![BlockStatement::Columns(parse_block_columns(
            source, start, end,
        )?)]);
    }
    if has_keyword(source, start, "classDef") {
        return Ok(vec![BlockStatement::ClassDef(shift_class_def(
            Parser::parse_flow_class_def(trimmed)?,
            start,
        ))]);
    }
    if has_keyword(source, start, "class") {
        return Ok(vec![BlockStatement::ClassApply(shift_class_apply(
            Parser::parse_flow_class_apply(trimmed)?,
            start,
        ))]);
    }
    if has_keyword(source, start, "style") {
        return Ok(vec![BlockStatement::Style(parse_block_style(
            source, start, end,
        )?)]);
    }
    if let Ok(edge) = Parser::parse_flow_edge(trimmed) {
        let edge = shift_edge(edge, start);
        let from_node = block_node_from_flow(edge.from.clone(), None);
        let to_node = block_node_from_flow(edge.to.clone(), None);
        return Ok(vec![BlockStatement::Edge(Box::new(BlockEdge {
            from: edge.from.id,
            to: edge.to.id,
            from_node,
            to_node,
            link: edge.link,
            label: edge.label,
            span: edge.span,
        }))]);
    }
    parse_block_items(source, start, end)
}

fn parse_block_columns(source: &str, start: usize, end: usize) -> Result<Spanned<u16>, ParseError> {
    if !has_keyword(source, start, "columns") {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownBlockStatement,
            span: Span::new(start, end),
        });
    }
    parse_block_width(source, start + "columns".len(), end)
}

fn parse_block_items(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<BlockStatement>, ParseError> {
    let mut statements = Vec::new();
    for token in block_item_tokens(source, start, end)? {
        statements.push(parse_block_item(source, token.start, token.end)?);
    }
    if statements.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownBlockStatement,
            span: Span::new(start, end),
        });
    }
    Ok(statements)
}

fn parse_block_item(source: &str, start: usize, end: usize) -> Result<BlockStatement, ParseError> {
    let (base_start, base_end, width) = split_block_width_suffix(source, start, end)?;
    let raw = &source[base_start..base_end];
    if raw == "space" {
        return Ok(BlockStatement::Space(BlockSpace {
            width,
            span: Span::new(start, end),
        }));
    }
    if let Some(node) = parse_block_arrow_node(source, base_start, base_end, width)? {
        return Ok(BlockStatement::Node(Box::new(
            node.with_span(Span::new(start, end)),
        )));
    }
    let flow = Parser::parse_flow_node(raw).map_err(|error| ParseError {
        kind: match error.kind {
            ParseErrorKind::ExpectedFlowNodeId
            | ParseErrorKind::MissingFlowNodeShape
            | ParseErrorKind::UnknownFlowNodeShape
            | ParseErrorKind::ReservedFlowNodeLabel
            | ParseErrorKind::UnterminatedFlowNodeShape
            | ParseErrorKind::TrailingInput => ParseErrorKind::ExpectedBlockNode,
            _ => error.kind,
        },
        span: Span::new(base_start + error.span.start, base_start + error.span.end),
    })?;
    Ok(BlockStatement::Node(Box::new(block_node_from_flow(
        shift_node(flow, base_start),
        Some(width),
    ))))
}

#[derive(Debug, Clone, Copy)]
struct BlockItemToken {
    start: usize,
    end: usize,
}

fn block_item_tokens(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<BlockItemToken>, ParseError> {
    let mut tokens = Vec::new();
    let mut token_start = None;
    let mut cursor = start;
    let mut quote = false;
    let mut square = 0i32;
    let mut paren = 0i32;
    let mut curly = 0i32;
    let mut angle = 0i32;
    let bytes = source.as_bytes();
    while cursor < end {
        let byte = bytes[cursor];
        match byte {
            b'"' => quote = !quote,
            b'[' if !quote => square += 1,
            b']' if !quote => square = square.saturating_sub(1),
            b'(' if !quote => paren += 1,
            b')' if !quote => paren = paren.saturating_sub(1),
            b'{' if !quote => curly += 1,
            b'}' if !quote => curly = curly.saturating_sub(1),
            b'<' if !quote => angle += 1,
            b'>' if !quote => angle = angle.saturating_sub(1),
            value
                if !quote
                    && square == 0
                    && paren == 0
                    && curly == 0
                    && angle == 0
                    && value.is_ascii_whitespace() =>
            {
                if let Some(token) = token_start.take() {
                    tokens.push(BlockItemToken {
                        start: token,
                        end: cursor,
                    });
                }
                cursor += 1;
                continue;
            }
            _ => {}
        }
        if token_start.is_none() && !byte.is_ascii_whitespace() {
            token_start = Some(cursor);
        }
        cursor += 1;
    }
    if quote || square != 0 || paren != 0 || curly != 0 || angle != 0 {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedBlockNode,
            span: Span::new(start, end),
        });
    }
    if let Some(token) = token_start {
        tokens.push(BlockItemToken { start: token, end });
    }
    Ok(tokens)
}

fn split_block_width_suffix(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(usize, usize, Spanned<u16>), ParseError> {
    let Some(colon) = top_level_width_colon(source, start, end) else {
        return Ok((start, end, Spanned::new(1, Span::new(end, end))));
    };
    let width = parse_block_width(source, colon + 1, end)?;
    Ok((start, colon, width))
}

fn top_level_width_colon(source: &str, start: usize, end: usize) -> Option<usize> {
    let bytes = source.as_bytes();
    let mut quote = false;
    let mut square = 0i32;
    let mut paren = 0i32;
    let mut curly = 0i32;
    let mut angle = 0i32;
    let mut colon = None;
    let mut cursor = start;
    while cursor < end {
        match bytes[cursor] {
            b'"' => quote = !quote,
            b'[' if !quote => square += 1,
            b']' if !quote => square = square.saturating_sub(1),
            b'(' if !quote => paren += 1,
            b')' if !quote => paren = paren.saturating_sub(1),
            b'{' if !quote => curly += 1,
            b'}' if !quote => curly = curly.saturating_sub(1),
            b'<' if !quote => angle += 1,
            b'>' if !quote => angle = angle.saturating_sub(1),
            b':' if !quote && square == 0 && paren == 0 && curly == 0 && angle == 0 => {
                colon = Some(cursor);
            }
            _ => {}
        }
        cursor += 1;
    }
    colon.filter(|colon| {
        *colon + 1 < end
            && source[*colon + 1..end]
                .bytes()
                .all(|byte| byte.is_ascii_digit())
    })
}

fn parse_block_width(source: &str, start: usize, end: usize) -> Result<Spanned<u16>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownBlockStatement,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let Ok(value) = source[absolute_start..absolute_end].parse::<u16>() else {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownBlockStatement,
            span: Span::new(absolute_start, absolute_end),
        });
    };
    if value == 0 {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownBlockStatement,
            span: Span::new(absolute_start, absolute_end),
        });
    }
    Ok(Spanned::new(value, Span::new(absolute_start, absolute_end)))
}

fn parse_block_arrow_node(
    source: &str,
    start: usize,
    end: usize,
    width: Spanned<u16>,
) -> Result<Option<BlockNode>, ParseError> {
    let Some(open_angle) = source[start..end].find("<[") else {
        return Ok(None);
    };
    let open_angle = start + open_angle;
    let id = parse_single_identifier(source, start, open_angle, ParseErrorKind::ExpectedBlockNode)?;
    let label_start = open_angle + "<[".len();
    let Some(label_close_offset) = source[label_start..end].find("]>") else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedBlockNode,
            span: Span::new(open_angle, end),
        });
    };
    let label_end = label_start + label_close_offset;
    let close = label_end + "]>".len();
    if source.as_bytes().get(close) != Some(&b'(')
        || source.as_bytes().get(end.saturating_sub(1)) != Some(&b')')
    {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedBlockNode,
            span: Span::new(close, end),
        });
    }
    let directions = parse_block_arrow_directions(source, close + 1, end - 1)?;
    Ok(Some(BlockNode {
        id,
        label: label_from_trimmed(source, label_start, label_end),
        shape: Spanned::new(BlockShape::Arrow(directions), Span::new(open_angle, end)),
        width,
        span: Span::new(start, end),
    }))
}

fn parse_block_arrow_directions(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<Spanned<BlockArrowDirection>>, ParseError> {
    let mut directions = Vec::new();
    for field in parse_sankey_csv_fields(source, start, end)? {
        let Some((trim_start, trim_end)) = trim_ascii_range(&source[field.start..field.end]) else {
            continue;
        };
        let absolute_start = field.start + trim_start;
        let absolute_end = field.start + trim_end;
        let Some(direction) =
            BlockArrowDirection::from_mermaid(&source[absolute_start..absolute_end])
        else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedBlockNode,
                span: Span::new(absolute_start, absolute_end),
            });
        };
        directions.push(Spanned::new(
            direction,
            Span::new(absolute_start, absolute_end),
        ));
    }
    if directions.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedBlockNode,
            span: Span::new(start, end),
        });
    }
    Ok(directions)
}

fn block_node_from_flow(node: FlowNode, width: Option<Spanned<u16>>) -> BlockNode {
    let span = node.span;
    BlockNode {
        id: node.id,
        label: node.label,
        shape: Spanned::new(BlockShape::Flow(node.shape.value), node.shape.span),
        width: width.unwrap_or_else(|| Spanned::new(1, Span::new(span.end, span.end))),
        span,
    }
}

trait BlockNodeSpan {
    fn with_span(self, span: Span) -> Self;
}

impl BlockNodeSpan for BlockNode {
    fn with_span(mut self, span: Span) -> Self {
        self.span = span;
        self
    }
}

fn parse_block_style(source: &str, start: usize, end: usize) -> Result<BlockStyle, ParseError> {
    let rest_start = start + "style".len();
    let target_start = next_non_ws(source, rest_start, end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedBlockNode,
        span: Span::new(rest_start, end),
    })?;
    let target_end = source[target_start..end]
        .find(|value: char| value.is_ascii_whitespace())
        .map_or(end, |offset| target_start + offset);
    let target = parse_single_identifier(
        source,
        target_start,
        target_end,
        ParseErrorKind::ExpectedBlockNode,
    )?;
    let styles_start = target_end;
    let styles = parse_style_declarations(source, styles_start, end)?;
    Ok(BlockStyle {
        target,
        styles,
        span: Span::new(start, end),
    })
}

fn parse_block_container_header(source: &str) -> Result<Option<BlockContainer>, ParseError> {
    let Some((start, end)) = trimmed_statement_bounds(source) else {
        return Ok(None);
    };
    if !source[start..end].starts_with("block")
        || source[start..end]
            .as_bytes()
            .get("block".len())
            .is_some_and(|byte| !byte.is_ascii_whitespace() && *byte != b':')
    {
        return Ok(None);
    }
    let mut cursor = start + "block".len();
    let mut id = None;
    let mut width = Spanned::new(1, Span::new(cursor, cursor));
    if source.as_bytes().get(cursor) == Some(&b':') {
        cursor += 1;
        let id_start = cursor;
        while source
            .as_bytes()
            .get(cursor)
            .is_some_and(|byte| byte.is_ascii_alphanumeric() || *byte == b'_' || *byte == b'-')
        {
            cursor += 1;
        }
        if cursor == id_start {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedBlockNode,
                span: Span::new(id_start, id_start),
            });
        }
        id = Some(Spanned::new(
            source[id_start..cursor].to_owned(),
            Span::new(id_start, cursor),
        ));
        if source.as_bytes().get(cursor) == Some(&b':') {
            let width_start = cursor + 1;
            let width_end = source[width_start..end]
                .find(|value: char| value.is_ascii_whitespace())
                .map_or(end, |offset| width_start + offset);
            width = parse_block_width(source, width_start, width_end)?;
            cursor = width_end;
        }
    }
    let columns = if let Some((rest_start, rest_end)) = trim_ascii_range(&source[cursor..end]) {
        let rest_start = cursor + rest_start;
        let rest_end = cursor + rest_end;
        Some(parse_block_columns(source, rest_start, rest_end)?)
    } else {
        None
    };
    Ok(Some(BlockContainer {
        id,
        width,
        columns,
        statements: Vec::new(),
        span: Span::new(start, end),
    }))
}

struct JourneyStatementParser<'source> {
    source: &'source str,
}

impl<'source> JourneyStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<JourneyStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownJourneyStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(JourneyStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(JourneyStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "title") {
            let label =
                label_from_trimmed(self.source, start + "title".len(), end).ok_or(ParseError {
                    kind: ParseErrorKind::UnknownJourneyStatement,
                    span: Span::new(start, end),
                })?;
            return Ok(JourneyStatement::Title(label));
        }
        if has_keyword(self.source, start, "section") {
            let label = label_from_trimmed(self.source, start + "section".len(), end).ok_or(
                ParseError {
                    kind: ParseErrorKind::UnknownJourneyStatement,
                    span: Span::new(start, end),
                },
            )?;
            return Ok(JourneyStatement::Section(label));
        }
        if let Some(task) = self.parse_task(start, end)? {
            return Ok(JourneyStatement::Task(Box::new(task)));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownJourneyStatement,
            span: Span::new(start, end),
        })
    }

    fn parse_task(&self, start: usize, end: usize) -> Result<Option<JourneyTask>, ParseError> {
        let Some(colon) = self.source[start..end].find(':') else {
            return Ok(None);
        };
        let colon = start + colon;
        let label = label_from_trimmed(self.source, start, colon).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedJourneyTask,
            span: Span::new(start, colon),
        })?;
        let (score, actors) = parse_journey_tail(self.source, colon + 1, end)?;
        Ok(Some(JourneyTask {
            label,
            section: None,
            score,
            actors,
            span: Span::new(start, end),
        }))
    }
}

struct GitGraphHeaderParser<'source> {
    source: &'source str,
}

impl<'source> GitGraphHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<GitGraphHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedGitGraphHeader,
                span: Span::new(0, 0),
            });
        };
        if !is_gitgraph_header_keyword(self.source, start, end) {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedGitGraphHeader,
                span: Span::new(start, end),
            });
        }
        let orientation_start = start + "gitGraph".len();
        let orientation = parse_gitgraph_orientation(self.source, orientation_start, end)?;
        Ok(GitGraphHeader {
            orientation,
            span: Span::new(start, end),
        })
    }
}

struct GitGraphStatementParser<'source> {
    source: &'source str,
}

impl<'source> GitGraphStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<GitGraphStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownGitGraphStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(GitGraphStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(GitGraphStatement::Comment(shift_comment(comment, start)));
        }
        if has_exact_keyword(self.source, start, end, "commit") {
            return Ok(GitGraphStatement::Commit(Box::new(parse_gitgraph_commit(
                self.source,
                start,
                end,
            )?)));
        }
        if has_keyword(self.source, start, "branch") {
            return Ok(GitGraphStatement::Branch(Box::new(parse_gitgraph_branch(
                self.source,
                start,
                end,
            )?)));
        }
        if has_keyword(self.source, start, "checkout") {
            let name = parse_gitgraph_keyword_name(self.source, start, end, "checkout")?;
            return Ok(GitGraphStatement::Checkout(name));
        }
        if has_keyword(self.source, start, "switch") {
            let name = parse_gitgraph_keyword_name(self.source, start, end, "switch")?;
            return Ok(GitGraphStatement::Checkout(name));
        }
        if has_keyword(self.source, start, "merge") {
            return Ok(GitGraphStatement::Merge(Box::new(parse_gitgraph_merge(
                self.source,
                start,
                end,
            )?)));
        }
        if has_keyword(self.source, start, "cherry-pick") {
            return Ok(GitGraphStatement::CherryPick(Box::new(
                parse_gitgraph_cherry_pick(self.source, start, end)?,
            )));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownGitGraphStatement,
            span: Span::new(start, end),
        })
    }
}

struct TimelineHeaderParser<'source> {
    source: &'source str,
}

impl<'source> TimelineHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<TimelineHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedTimelineHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "timeline" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedTimelineHeader,
                span: Span::new(start, end),
            });
        }
        Ok(TimelineHeader {
            span: Span::new(start, end),
        })
    }
}

struct TimelineStatementParser<'source> {
    source: &'source str,
}

impl<'source> TimelineStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<TimelineStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownTimelineStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(TimelineStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(TimelineStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "title") {
            let label =
                label_from_trimmed(self.source, start + "title".len(), end).ok_or(ParseError {
                    kind: ParseErrorKind::UnknownTimelineStatement,
                    span: Span::new(start, end),
                })?;
            return Ok(TimelineStatement::Title(label));
        }
        if has_keyword(self.source, start, "section") {
            let label = label_from_trimmed(self.source, start + "section".len(), end).ok_or(
                ParseError {
                    kind: ParseErrorKind::UnknownTimelineStatement,
                    span: Span::new(start, end),
                },
            )?;
            return Ok(TimelineStatement::Section(label));
        }
        if self.source.as_bytes()[start] == b':' {
            let event = parse_timeline_event(self.source, start + 1, end)?;
            return Ok(TimelineStatement::Event(event));
        }
        if let Some(period) = parse_timeline_period(self.source, start, end)? {
            return Ok(TimelineStatement::Period(Box::new(period)));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownTimelineStatement,
            span: Span::new(start, end),
        })
    }
}

struct RequirementHeaderParser<'source> {
    source: &'source str,
}

impl<'source> RequirementHeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<RequirementHeader, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedRequirementHeader,
                span: Span::new(0, 0),
            });
        };
        if &self.source[start..end] != "requirementDiagram" {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedRequirementHeader,
                span: Span::new(start, end),
            });
        }
        Ok(RequirementHeader {
            span: Span::new(start, end),
        })
    }
}

struct RequirementStatementParser<'source> {
    source: &'source str,
}

impl<'source> RequirementStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<RequirementStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownRequirementStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(RequirementStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(RequirementStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "direction") {
            let direction = parse_requirement_direction(self.source, start, end)?;
            return Ok(RequirementStatement::Direction(direction));
        }
        if has_keyword(self.source, start, "style") {
            return Ok(RequirementStatement::Style(parse_requirement_style(
                self.source,
                start,
                end,
            )?));
        }
        if has_keyword(self.source, start, "classDef") {
            return Ok(RequirementStatement::ClassDef(shift_class_def(
                Parser::parse_flow_class_def(&self.source[start..end])?,
                start,
            )));
        }
        if has_keyword(self.source, start, "class") {
            return Ok(RequirementStatement::ClassApply(shift_class_apply(
                Parser::parse_flow_class_apply(&self.source[start..end])?,
                start,
            )));
        }
        if let Some(class_apply) = parse_requirement_class_shorthand(self.source, start, end)? {
            return Ok(RequirementStatement::ClassApply(class_apply));
        }
        if let Some(relationship) = parse_requirement_relationship(self.source, start, end)? {
            return Ok(RequirementStatement::Relationship(Box::new(relationship)));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownRequirementStatement,
            span: Span::new(start, end),
        })
    }
}

struct C4HeaderParser<'source> {
    source: &'source str,
}

impl<'source> C4HeaderParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<C4Header, ParseError> {
        let Some((start, end)) = trim_ascii_range(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedC4Header,
                span: Span::new(0, 0),
            });
        };
        let diagram_type = match &self.source[start..end] {
            "C4Context" => C4DiagramType::Context,
            "C4Container" => C4DiagramType::Container,
            "C4Component" => C4DiagramType::Component,
            "C4Dynamic" => C4DiagramType::Dynamic,
            "C4Deployment" => C4DiagramType::Deployment,
            _ => {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedC4Header,
                    span: Span::new(start, end),
                });
            }
        };
        Ok(C4Header {
            diagram_type: Spanned::new(diagram_type, Span::new(start, end)),
            span: Span::new(start, end),
        })
    }
}

struct C4StatementParser<'source> {
    source: &'source str,
}

impl<'source> C4StatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<C4Statement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownC4Statement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(C4Statement::Directive(shift_directive(directive, start)));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(C4Statement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "title") {
            let title =
                label_from_trimmed(self.source, start + "title".len(), end).ok_or(ParseError {
                    kind: ParseErrorKind::UnknownC4Statement,
                    span: Span::new(start, end),
                })?;
            return Ok(C4Statement::Title(title));
        }
        let call = parse_c4_call(self.source, start, end)?;
        if let Some(element) = c4_element_from_call(&call)? {
            return Ok(C4Statement::Element(Box::new(element)));
        }
        if let Some(boundary) = c4_boundary_from_call(&call)? {
            return Ok(C4Statement::Boundary(Box::new(boundary)));
        }
        if let Some(relationship) = c4_relationship_from_call(&call)? {
            return Ok(C4Statement::Relationship(Box::new(relationship)));
        }
        if let Some(style) = c4_style_from_call(&call)? {
            return Ok(C4Statement::Style(style));
        }
        if is_c4_layout_call(&call.name.value) {
            return Ok(C4Statement::Layout(C4LayoutConfig {
                name: call.name,
                fields: call.args,
                span: call.span,
            }));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownC4Statement,
            span: Span::new(start, end),
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
        if let Some(label) = &label {
            reject_reserved_flow_label(label)?;
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

fn has_exact_keyword(source: &str, start: usize, end: usize, keyword: &str) -> bool {
    &source[start..end] == keyword || has_keyword(source, start, keyword)
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

fn next_non_ws(source: &str, start: usize, end: usize) -> Option<usize> {
    let mut cursor = start;
    while cursor < end && source.as_bytes()[cursor].is_ascii_whitespace() {
        cursor += 1;
    }
    (cursor < end).then_some(cursor)
}

fn parse_sequence_number_values(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<Spanned<String>>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Ok(Vec::new());
    };
    let mut values = Vec::new();
    let mut cursor = start + trim_start;
    let end = start + trim_end;
    while cursor < end {
        while cursor < end && source.as_bytes()[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        let value_start = cursor;
        while cursor < end && !source.as_bytes()[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        if value_start == cursor {
            break;
        }
        let value = &source[value_start..cursor];
        if !is_sequence_number(value) || values.len() >= 2 {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownSequenceStatement,
                span: Span::new(value_start, cursor),
            });
        }
        values.push(Spanned::new(
            value.to_owned(),
            Span::new(value_start, cursor),
        ));
    }
    Ok(values)
}

fn is_sequence_number(value: &str) -> bool {
    let Some((integer, fraction)) = value.split_once('.') else {
        return !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit());
    };
    !integer.is_empty()
        && integer.bytes().all(|byte| byte.is_ascii_digit())
        && (1..=2).contains(&fraction.len())
        && fraction.bytes().all(|byte| byte.is_ascii_digit())
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

fn parse_class_source_endpoint(
    source: &str,
    start: usize,
    end: usize,
    error_kind: ParseErrorKind,
) -> Result<(Spanned<String>, Option<Label>), ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: error_kind,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let Some(cardinality_start) =
        trailing_quoted_class_cardinality_start(source, absolute_start, absolute_end)
    else {
        return parse_single_identifier(source, absolute_start, absolute_end, error_kind)
            .map(|id| (id, None));
    };
    let id = parse_single_identifier(source, absolute_start, cardinality_start, error_kind)?;
    let cardinality = label_from_body(source, cardinality_start, absolute_end);

    Ok((id, Some(cardinality)))
}

fn parse_class_target_endpoint(
    source: &str,
    start: usize,
    end: usize,
    error_kind: ParseErrorKind,
) -> Result<(Spanned<String>, Option<Label>), ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: error_kind,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    if source.as_bytes().get(absolute_start) != Some(&b'"') {
        return parse_single_identifier(source, absolute_start, absolute_end, error_kind)
            .map(|id| (id, None));
    }
    let close_quote = source[absolute_start + 1..absolute_end]
        .find('"')
        .map(|offset| absolute_start + 1 + offset)
        .ok_or(ParseError {
            kind: error_kind,
            span: Span::new(absolute_start, absolute_end),
        })?;
    let cardinality = label_from_body(source, absolute_start, close_quote + 1);
    let id = parse_single_identifier(source, close_quote + 1, absolute_end, error_kind)?;

    Ok((id, Some(cardinality)))
}

fn trailing_quoted_class_cardinality_start(
    source: &str,
    start: usize,
    end: usize,
) -> Option<usize> {
    if end <= start || source.as_bytes().get(end - 1) != Some(&b'"') {
        return None;
    }
    let mut cursor = end - 1;
    while cursor > start {
        cursor -= 1;
        if source.as_bytes()[cursor] == b'"' {
            return Some(cursor);
        }
    }
    None
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

fn parse_gantt_value(
    source: &str,
    start: usize,
    end: usize,
    keyword: &str,
) -> Result<Spanned<String>, ParseError> {
    let value_start = start + keyword.len();
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[value_start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownGanttStatement,
            span: Span::new(value_start, end),
        });
    };
    let absolute_start = value_start + trim_start;
    let absolute_end = value_start + trim_end;
    Ok(Spanned::new(
        source[absolute_start..absolute_end].to_owned(),
        Span::new(absolute_start, absolute_end),
    ))
}

fn parse_gantt_metadata(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<Spanned<String>>, ParseError> {
    let mut values = Vec::new();
    let mut part_start = start;
    while part_start <= end {
        let part_end = source[part_start..end]
            .find(',')
            .map_or(end, |offset| part_start + offset);
        if let Some((trim_start, trim_end)) = trim_ascii_range(&source[part_start..part_end]) {
            let absolute_start = part_start + trim_start;
            let absolute_end = part_start + trim_end;
            values.push(Spanned::new(
                source[absolute_start..absolute_end].to_owned(),
                Span::new(absolute_start, absolute_end),
            ));
        }
        if part_end == end {
            break;
        }
        part_start = part_end + 1;
    }
    if values.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedGanttMetadata,
            span: Span::new(start, end),
        });
    }
    Ok(values)
}

fn take_gantt_tags(metadata: &mut Vec<Spanned<String>>) -> Vec<GanttTaskTag> {
    let mut tags = Vec::new();
    while let Some(tag) = metadata.first().and_then(|value| gantt_tag(&value.value)) {
        tags.push(tag);
        metadata.remove(0);
    }
    tags
}

fn gantt_tag(value: &str) -> Option<GanttTaskTag> {
    match value {
        "active" => Some(GanttTaskTag::Active),
        "done" => Some(GanttTaskTag::Done),
        "crit" => Some(GanttTaskTag::Crit),
        "milestone" => Some(GanttTaskTag::Milestone),
        _ => None,
    }
}

fn parse_pie_value(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(Spanned<u64>, Spanned<String>), ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedPieValue,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let raw = &source[absolute_start..absolute_end];
    let Some(units) = parse_pie_value_units(raw) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedPieValue,
            span: Span::new(absolute_start, absolute_end),
        });
    };
    Ok((
        Spanned::new(units, Span::new(absolute_start, absolute_end)),
        Spanned::new(raw.to_owned(), Span::new(absolute_start, absolute_end)),
    ))
}

fn parse_pie_value_units(value: &str) -> Option<u64> {
    let (whole, fraction) = value
        .split_once('.')
        .map_or((value, ""), |(whole, fraction)| (whole, fraction));
    if whole.is_empty()
        || !whole.bytes().all(|byte| byte.is_ascii_digit())
        || fraction.len() > 2
        || !fraction.bytes().all(|byte| byte.is_ascii_digit())
    {
        return None;
    }
    let whole_units = whole.parse::<u64>().ok()?.checked_mul(100)?;
    let fraction_units = match fraction.len() {
        0 => 0,
        1 => fraction.parse::<u64>().ok()?.checked_mul(10)?,
        2 => fraction.parse::<u64>().ok()?,
        _ => return None,
    };
    let units = whole_units.checked_add(fraction_units)?;
    (units > 0).then_some(units)
}

fn parse_quadrant_value(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<u16>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedQuadrantValue,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let raw = &source[absolute_start..absolute_end];
    let Ok(value) = raw.parse::<f64>() else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedQuadrantValue,
            span: Span::new(absolute_start, absolute_end),
        });
    };
    if !value.is_finite() || !(0.0..=1.0).contains(&value) {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedQuadrantValue,
            span: Span::new(absolute_start, absolute_end),
        });
    }
    Ok(Spanned::new(
        (value * 1000.0).round() as u16,
        Span::new(absolute_start, absolute_end),
    ))
}

fn parse_packet_field(
    source: &str,
    start: usize,
    end: usize,
    next_bit: u32,
) -> Result<PacketField, ParseError> {
    let end = packet_statement_content_end(source, start, end);
    let Some(colon) = source[start..end].find(':').map(|offset| start + offset) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedPacketField,
            span: Span::new(start, end),
        });
    };
    let range = parse_packet_range(source, start, colon, next_bit)?;
    let label = label_from_trimmed(source, colon + 1, end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedPacketField,
        span: Span::new(colon + 1, end),
    })?;
    Ok(PacketField {
        range,
        label,
        span: Span::new(start, end),
    })
}

fn packet_statement_content_end(source: &str, start: usize, end: usize) -> usize {
    let mut content_end = find_packet_inline_comment(source, start, end).unwrap_or(end);
    while content_end > start && source.as_bytes()[content_end - 1].is_ascii_whitespace() {
        content_end -= 1;
    }
    if source.as_bytes().get(content_end.saturating_sub(1)) == Some(&b';') {
        content_end -= 1;
        while content_end > start && source.as_bytes()[content_end - 1].is_ascii_whitespace() {
            content_end -= 1;
        }
    }
    content_end
}

fn find_packet_inline_comment(source: &str, start: usize, end: usize) -> Option<usize> {
    let bytes = source.as_bytes();
    let mut cursor = start;
    let mut quote = false;
    while cursor + 1 < end {
        match bytes[cursor] {
            b'"' if cursor == start || bytes.get(cursor.wrapping_sub(1)) != Some(&b'\\') => {
                quote = !quote;
            }
            b'%' if !quote && bytes[cursor + 1] == b'%' => return Some(cursor),
            _ => {}
        }
        cursor += 1;
    }
    None
}

fn parse_packet_range(
    source: &str,
    start: usize,
    end: usize,
    next_bit: u32,
) -> Result<PacketRange, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedPacketRange,
            span: Span::new(start, end),
        });
    };
    let range_start = start + trim_start;
    let range_end = start + trim_end;
    if source.as_bytes()[range_start] == b'+' {
        let count = parse_packet_bit_number(source, range_start + 1, range_end)?;
        if count.value == 0 {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedPacketRange,
                span: Span::new(range_start, range_end),
            });
        }
        let end_bit = next_bit.checked_add(count.value - 1).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedPacketRange,
            span: Span::new(range_start, range_end),
        })?;
        return Ok(PacketRange {
            start: Spanned::new(next_bit, Span::new(range_start, range_end)),
            end: Spanned::new(end_bit, count.span),
            span: Span::new(range_start, range_end),
        });
    }
    if let Some(dash) = source[range_start..range_end].find('-') {
        let dash = range_start + dash;
        let start_bit = parse_packet_bit_number(source, range_start, dash)?;
        let end_bit = parse_packet_bit_number(source, dash + 1, range_end)?;
        if end_bit.value < start_bit.value {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedPacketRange,
                span: Span::new(range_start, range_end),
            });
        }
        return Ok(PacketRange {
            start: start_bit,
            end: end_bit,
            span: Span::new(range_start, range_end),
        });
    }
    let bit = parse_packet_bit_number(source, range_start, range_end)?;
    Ok(PacketRange {
        start: bit,
        end: bit,
        span: Span::new(range_start, range_end),
    })
}

fn parse_packet_bit_number(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<u32>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedPacketRange,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    if !source.as_bytes()[absolute_start..absolute_end]
        .iter()
        .all(u8::is_ascii_digit)
    {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedPacketRange,
            span: Span::new(absolute_start, absolute_end),
        });
    }
    let value = source[absolute_start..absolute_end]
        .parse::<u32>()
        .map_err(|_| ParseError {
            kind: ParseErrorKind::ExpectedPacketRange,
            span: Span::new(absolute_start, absolute_end),
        })?;
    Ok(Spanned::new(value, Span::new(absolute_start, absolute_end)))
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct KanbanParsedItem {
    id: Option<Spanned<String>>,
    label: Label,
    metadata: Vec<KanbanMetadata>,
    span: Span,
}

impl KanbanParsedItem {
    fn into_column(self) -> KanbanColumn {
        KanbanColumn {
            id: self.id,
            title: self.label,
            tasks: Vec::new(),
            span: self.span,
        }
    }

    fn into_task(self) -> KanbanTask {
        KanbanTask {
            id: self.id,
            label: self.label,
            metadata: self.metadata,
            span: self.span,
        }
    }
}

fn parse_kanban_item(
    source: &str,
    start: usize,
    end: usize,
) -> Result<KanbanParsedItem, ParseError> {
    let content_end = kanban_item_content_end(source, start, end);
    let metadata_start = find_kanban_metadata_start(source, start, content_end);
    let metadata = if let Some(metadata_start) = metadata_start {
        parse_kanban_metadata(source, metadata_start, content_end)?
    } else {
        Vec::new()
    };
    let item_end = metadata_start.unwrap_or(content_end).min(content_end);
    let Some((item_start, item_end)) = trim_ascii_range(&source[start..item_end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedKanbanItem,
            span: Span::new(start, end),
        });
    };
    let item_start = start + item_start;
    let item_end = start + item_end;
    let (id, label) = parse_kanban_item_label(source, item_start, item_end)?;
    Ok(KanbanParsedItem {
        id,
        label,
        metadata,
        span: Span::new(item_start, content_end),
    })
}

fn kanban_item_content_end(source: &str, start: usize, end: usize) -> usize {
    let mut content_end = end;
    while content_end > start && source.as_bytes()[content_end - 1].is_ascii_whitespace() {
        content_end -= 1;
    }
    if source.as_bytes().get(content_end.saturating_sub(1)) == Some(&b';') {
        content_end -= 1;
        while content_end > start && source.as_bytes()[content_end - 1].is_ascii_whitespace() {
            content_end -= 1;
        }
    }
    content_end
}

fn parse_kanban_item_label(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(Option<Spanned<String>>, Label), ParseError> {
    if source.as_bytes().get(start) == Some(&b'[') {
        if source.as_bytes().get(end.saturating_sub(1)) != Some(&b']') {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedKanbanItem,
                span: Span::new(start, end),
            });
        }
        return Ok((None, label_from_body(source, start + 1, end - 1)));
    }
    if let Some(open) = find_kanban_label_open(source, start, end) {
        if source.as_bytes().get(end.saturating_sub(1)) != Some(&b']') {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedKanbanItem,
                span: Span::new(open, end),
            });
        }
        let id = parse_kanban_id(source, start, open)?;
        let label = label_from_body(source, open + 1, end - 1);
        return Ok((Some(id), label));
    }
    let label = label_from_trimmed(source, start, end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedKanbanItem,
        span: Span::new(start, end),
    })?;
    Ok((None, label))
}

fn parse_kanban_id(source: &str, start: usize, end: usize) -> Result<Spanned<String>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedKanbanItem,
            span: Span::new(start, end),
        });
    };
    let id_start = start + trim_start;
    let id_end = start + trim_end;
    Ok(Spanned::new(
        source[id_start..id_end].to_owned(),
        Span::new(id_start, id_end),
    ))
}

fn find_kanban_label_open(source: &str, start: usize, end: usize) -> Option<usize> {
    source[start..end].find('[').map(|offset| start + offset)
}

fn find_kanban_metadata_start(source: &str, start: usize, end: usize) -> Option<usize> {
    let bytes = source.as_bytes();
    let mut cursor = start;
    let mut quote = None;
    let mut square = 0u16;
    while cursor + 1 < end {
        match bytes[cursor] {
            byte if quote == Some(byte) => quote = None,
            b'\'' | b'"' if quote.is_none() => quote = Some(bytes[cursor]),
            b'[' if quote.is_none() => square += 1,
            b']' if quote.is_none() => square = square.saturating_sub(1),
            b'@' if quote.is_none() && square == 0 && bytes[cursor + 1] == b'{' => {
                return Some(cursor);
            }
            _ => {}
        }
        cursor += 1;
    }
    None
}

fn parse_kanban_metadata(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<KanbanMetadata>, ParseError> {
    if !source[start..end].starts_with("@{") || source.as_bytes().get(end - 1) != Some(&b'}') {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedKanbanMetadata,
            span: Span::new(start, end),
        });
    }
    let mut metadata = Vec::new();
    for field in split_kanban_metadata_fields(source, start + 2, end - 1)? {
        let Some(colon) = find_kanban_metadata_colon(source, field.start, field.end) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedKanbanMetadata,
                span: Span::new(field.start, field.end),
            });
        };
        let key = parse_kanban_id(source, field.start, colon).map_err(|_| ParseError {
            kind: ParseErrorKind::ExpectedKanbanMetadata,
            span: Span::new(field.start, colon),
        })?;
        let value = kanban_metadata_value(source, colon + 1, field.end)?;
        metadata.push(KanbanMetadata {
            span: Span::new(field.start, field.end),
            key,
            value,
        });
    }
    Ok(metadata)
}

#[derive(Debug, Clone, Copy)]
struct KanbanMetadataField {
    start: usize,
    end: usize,
}

fn split_kanban_metadata_fields(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<KanbanMetadataField>, ParseError> {
    let mut fields = Vec::new();
    let mut cursor = start;
    let mut field_start = start;
    let mut quote = None;
    while cursor < end {
        let byte = source.as_bytes()[cursor];
        if quote == Some(byte) {
            quote = None;
        } else if quote.is_none() && matches!(byte, b'\'' | b'"') {
            quote = Some(byte);
        } else if quote.is_none() && byte == b',' {
            push_kanban_metadata_field(source, field_start, cursor, &mut fields);
            field_start = cursor + 1;
        }
        cursor += 1;
    }
    if quote.is_some() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedKanbanMetadata,
            span: Span::new(start, end),
        });
    }
    push_kanban_metadata_field(source, field_start, end, &mut fields);
    Ok(fields)
}

fn push_kanban_metadata_field(
    source: &str,
    start: usize,
    end: usize,
    fields: &mut Vec<KanbanMetadataField>,
) {
    if let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) {
        fields.push(KanbanMetadataField {
            start: start + trim_start,
            end: start + trim_end,
        });
    }
}

fn find_kanban_metadata_colon(source: &str, start: usize, end: usize) -> Option<usize> {
    let mut cursor = start;
    let mut quote = None;
    while cursor < end {
        let byte = source.as_bytes()[cursor];
        if quote == Some(byte) {
            quote = None;
        } else if quote.is_none() && matches!(byte, b'\'' | b'"') {
            quote = Some(byte);
        } else if quote.is_none() && byte == b':' {
            return Some(cursor);
        }
        cursor += 1;
    }
    None
}

fn kanban_metadata_value(source: &str, start: usize, end: usize) -> Result<Label, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedKanbanMetadata,
            span: Span::new(start, end),
        });
    };
    let value_start = start + trim_start;
    let value_end = start + trim_end;
    let bytes = source.as_bytes();
    if value_end > value_start + 1
        && matches!(bytes[value_start], b'\'' | b'"')
        && bytes[value_end - 1] == bytes[value_start]
    {
        return Ok(Label {
            text: source[value_start + 1..value_end - 1].to_owned(),
            kind: LabelKind::String,
            span: Span::new(value_start + 1, value_end - 1),
        });
    }
    Ok(label_from_body(source, value_start, value_end))
}

struct ArchitectureStatementParser<'source> {
    source: &'source str,
}

impl<'source> ArchitectureStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<ArchitectureStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownArchitectureStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(ArchitectureStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(ArchitectureStatement::Comment(shift_comment(
                comment, start,
            )));
        }
        if has_keyword(self.source, start, "group") {
            return parse_architecture_component(self.source, start, end, "group")
                .map(|component| ArchitectureStatement::Group(Box::new(component.into_group())));
        }
        if has_keyword(self.source, start, "service") {
            return parse_architecture_component(self.source, start, end, "service").map(
                |component| ArchitectureStatement::Service(Box::new(component.into_service())),
            );
        }
        if has_keyword(self.source, start, "junction") {
            return parse_architecture_junction(self.source, start, end)
                .map(|junction| ArchitectureStatement::Junction(Box::new(junction)));
        }
        if has_keyword(self.source, start, "align") {
            return parse_architecture_alignment(self.source, start, end)
                .map(|alignment| ArchitectureStatement::Alignment(Box::new(alignment)));
        }
        if self.source[start..end].contains("--") {
            return parse_architecture_edge(self.source, start, end)
                .map(|edge| ArchitectureStatement::Edge(Box::new(edge)));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownArchitectureStatement,
            span: Span::new(start, end),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ArchitectureComponent {
    id: Spanned<String>,
    icon: Option<Label>,
    title: Option<Label>,
    parent: Option<Spanned<String>>,
    span: Span,
}

impl ArchitectureComponent {
    fn into_group(self) -> ArchitectureGroup {
        ArchitectureGroup {
            id: self.id,
            icon: self.icon,
            title: self.title,
            parent: self.parent,
            span: self.span,
        }
    }

    fn into_service(self) -> ArchitectureService {
        ArchitectureService {
            id: self.id,
            icon: self.icon,
            title: self.title,
            parent: self.parent,
            span: self.span,
        }
    }
}

fn parse_architecture_component(
    source: &str,
    start: usize,
    end: usize,
    keyword: &str,
) -> Result<ArchitectureComponent, ParseError> {
    let mut cursor = start + keyword.len();
    cursor = skip_ascii_ws(source, cursor, end);
    let id = parse_architecture_id(
        source,
        cursor,
        end,
        ParseErrorKind::ExpectedArchitectureNode,
    )?;
    cursor = id.span.end;
    let icon = if source.as_bytes().get(cursor) == Some(&b'(') {
        let close = source[cursor + 1..end]
            .find(')')
            .map(|offset| cursor + 1 + offset)
            .ok_or(ParseError {
                kind: ParseErrorKind::ExpectedArchitectureNode,
                span: Span::new(cursor, end),
            })?;
        let icon = label_from_body(source, cursor + 1, close);
        cursor = close + 1;
        Some(icon)
    } else {
        None
    };
    let title = if source.as_bytes().get(cursor) == Some(&b'[') {
        let close = source[cursor + 1..end]
            .find(']')
            .map(|offset| cursor + 1 + offset)
            .ok_or(ParseError {
                kind: ParseErrorKind::ExpectedArchitectureNode,
                span: Span::new(cursor, end),
            })?;
        let title = label_from_body(source, cursor + 1, close);
        cursor = close + 1;
        Some(title)
    } else {
        None
    };
    let parent = parse_architecture_optional_parent(source, cursor, end)?;
    Ok(ArchitectureComponent {
        id,
        icon,
        title,
        parent,
        span: Span::new(start, end),
    })
}

fn parse_architecture_junction(
    source: &str,
    start: usize,
    end: usize,
) -> Result<ArchitectureJunction, ParseError> {
    let mut cursor = start + "junction".len();
    cursor = skip_ascii_ws(source, cursor, end);
    let id = parse_architecture_id(
        source,
        cursor,
        end,
        ParseErrorKind::ExpectedArchitectureNode,
    )?;
    let parent = parse_architecture_optional_parent(source, id.span.end, end)?;
    Ok(ArchitectureJunction {
        id,
        parent,
        span: Span::new(start, end),
    })
}

fn parse_architecture_optional_parent(
    source: &str,
    cursor: usize,
    end: usize,
) -> Result<Option<Spanned<String>>, ParseError> {
    let cursor = skip_ascii_ws(source, cursor, end);
    if cursor >= end {
        return Ok(None);
    }
    if !has_keyword(source, cursor, "in") {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureNode,
            span: Span::new(cursor, end),
        });
    }
    let parent_start = skip_ascii_ws(source, cursor + 2, end);
    let parent = parse_architecture_id(
        source,
        parent_start,
        end,
        ParseErrorKind::ExpectedArchitectureNode,
    )?;
    if trim_ascii_range(&source[parent.span.end..end]).is_some() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureNode,
            span: Span::new(parent.span.end, end),
        });
    }
    Ok(Some(parent))
}

fn parse_architecture_edge(
    source: &str,
    start: usize,
    end: usize,
) -> Result<ArchitectureEdge, ParseError> {
    let tokens = architecture_tokens(source, start, end);
    let [left, link, right] = tokens.as_slice() else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureEdge,
            span: Span::new(start, end),
        });
    };
    let (arrow_start, arrow_end) = parse_architecture_link(source, *link)?;
    Ok(ArchitectureEdge {
        from: parse_architecture_left_endpoint(source, *left)?,
        to: parse_architecture_right_endpoint(source, *right)?,
        arrow_start,
        arrow_end,
        span: Span::new(start, end),
    })
}

fn architecture_tokens(source: &str, start: usize, end: usize) -> Vec<Span> {
    let mut tokens = Vec::new();
    let mut cursor = start;
    while cursor < end {
        cursor = skip_ascii_ws(source, cursor, end);
        if cursor >= end {
            break;
        }
        let token_start = cursor;
        while cursor < end && !source.as_bytes()[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        tokens.push(Span::new(token_start, cursor));
    }
    tokens
}

fn parse_architecture_link(source: &str, span: Span) -> Result<(bool, bool), ParseError> {
    let link = &source[span.start..span.end];
    let body = link.strip_prefix('<').map_or(link, |stripped| stripped);
    let arrow_start = body.len() != link.len();
    let body_without_end = body.strip_suffix('>').map_or(body, |stripped| stripped);
    let arrow_end = body_without_end.len() != body.len();
    if body_without_end != "--" {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureEdge,
            span,
        });
    }
    Ok((arrow_start, arrow_end))
}

fn parse_architecture_left_endpoint(
    source: &str,
    span: Span,
) -> Result<ArchitectureEndpoint, ParseError> {
    let colon = source[span.start..span.end]
        .find(':')
        .map(|offset| span.start + offset)
        .ok_or(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureEdge,
            span,
        })?;
    let (id, group) = parse_architecture_endpoint_id(source, span.start, colon)?;
    let side = parse_architecture_side(source, colon + 1, span.end)?;
    Ok(ArchitectureEndpoint {
        id,
        side,
        group,
        span,
    })
}

fn parse_architecture_right_endpoint(
    source: &str,
    span: Span,
) -> Result<ArchitectureEndpoint, ParseError> {
    let colon = source[span.start..span.end]
        .find(':')
        .map(|offset| span.start + offset)
        .ok_or(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureEdge,
            span,
        })?;
    let side = parse_architecture_side(source, span.start, colon)?;
    let (id, group) = parse_architecture_endpoint_id(source, colon + 1, span.end)?;
    Ok(ArchitectureEndpoint {
        id,
        side,
        group,
        span,
    })
}

fn parse_architecture_endpoint_id(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(Spanned<String>, bool), ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureEdge,
            span: Span::new(start, end),
        });
    };
    let mut id_start = start + trim_start;
    let mut id_end = start + trim_end;
    let mut group = false;
    if source[id_start..id_end].ends_with("{group}") {
        id_end -= "{group}".len();
        group = true;
        let Some((inner_start, inner_end)) = trim_ascii_range(&source[id_start..id_end]) else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedArchitectureEdge,
                span: Span::new(start, end),
            });
        };
        id_start += inner_start;
        id_end = start + trim_start + inner_end;
    }
    if id_start >= id_end {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureEdge,
            span: Span::new(start, end),
        });
    }
    Ok((
        Spanned::new(
            source[id_start..id_end].to_owned(),
            Span::new(id_start, id_end),
        ),
        group,
    ))
}

fn parse_architecture_side(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<ArchitectureSide>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureSide,
            span: Span::new(start, end),
        });
    };
    let side_start = start + trim_start;
    let side_end = start + trim_end;
    let Some(side) = ArchitectureSide::from_mermaid(&source[side_start..side_end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureSide,
            span: Span::new(side_start, side_end),
        });
    };
    Ok(Spanned::new(side, Span::new(side_start, side_end)))
}

fn parse_architecture_alignment(
    source: &str,
    start: usize,
    end: usize,
) -> Result<ArchitectureAlignment, ParseError> {
    let tokens = architecture_tokens(source, start, end);
    if tokens.len() < 4 {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureAlignment,
            span: Span::new(start, end),
        });
    }
    let axis_span = tokens[1];
    let Some(axis) = ArchitectureAlignAxis::from_mermaid(&source[axis_span.start..axis_span.end])
    else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedArchitectureAlignment,
            span: axis_span,
        });
    };
    let members = tokens[2..]
        .iter()
        .map(|span| {
            Spanned::new(
                source[span.start..span.end].to_owned(),
                Span::new(span.start, span.end),
            )
        })
        .collect();
    Ok(ArchitectureAlignment {
        axis: Spanned::new(axis, axis_span),
        members,
        span: Span::new(start, end),
    })
}

fn parse_architecture_id(
    source: &str,
    start: usize,
    end: usize,
    kind: ParseErrorKind,
) -> Result<Spanned<String>, ParseError> {
    let mut cursor = start;
    while cursor < end
        && !source.as_bytes()[cursor].is_ascii_whitespace()
        && !matches!(source.as_bytes()[cursor], b'(' | b'[')
    {
        cursor += 1;
    }
    if cursor == start {
        return Err(ParseError {
            kind,
            span: Span::new(start, end),
        });
    }
    Ok(Spanned::new(
        source[start..cursor].to_owned(),
        Span::new(start, cursor),
    ))
}

fn skip_ascii_ws(source: &str, mut cursor: usize, end: usize) -> usize {
    while cursor < end && source.as_bytes()[cursor].is_ascii_whitespace() {
        cursor += 1;
    }
    cursor
}

struct RadarStatementParser<'source> {
    source: &'source str,
}

impl<'source> RadarStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<Vec<RadarStatement>, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownRadarStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(vec![RadarStatement::Directive(shift_directive(
                directive, start,
            ))]);
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(vec![RadarStatement::Comment(shift_comment(comment, start))]);
        }
        if has_keyword(self.source, start, "title") {
            let label_start = skip_ascii_ws(self.source, start + "title".len(), end);
            let label = label_from_trimmed(self.source, label_start, end).ok_or(ParseError {
                kind: ParseErrorKind::UnknownRadarStatement,
                span: Span::new(start, end),
            })?;
            return Ok(vec![RadarStatement::Title(label)]);
        }
        if has_keyword(self.source, start, "axis") {
            return parse_radar_axes(self.source, start + "axis".len(), end);
        }
        if has_keyword(self.source, start, "curve") {
            return parse_radar_curves(self.source, start + "curve".len(), end);
        }
        if let Some(option) = parse_radar_option(self.source, start, end)? {
            return Ok(vec![RadarStatement::Option(Box::new(option))]);
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownRadarStatement,
            span: Span::new(start, end),
        })
    }
}

fn parse_radar_axes(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<RadarStatement>, ParseError> {
    let fields = split_radar_fields(source, start, end)?;
    if fields.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRadarAxis,
            span: Span::new(start, end),
        });
    }
    fields
        .into_iter()
        .map(|span| {
            parse_radar_labelled_id(source, span, ParseErrorKind::ExpectedRadarAxis)
                .map(|(id, label)| RadarStatement::Axis(Box::new(RadarAxis { id, label, span })))
        })
        .collect()
}

fn parse_radar_curves(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<RadarStatement>, ParseError> {
    let fields = split_radar_fields(source, start, end)?;
    if fields.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRadarCurve,
            span: Span::new(start, end),
        });
    }
    fields
        .into_iter()
        .map(|span| {
            parse_radar_curve(source, span).map(|curve| RadarStatement::Curve(Box::new(curve)))
        })
        .collect()
}

fn parse_radar_curve(source: &str, span: Span) -> Result<RadarCurve, ParseError> {
    let open = find_radar_top_level_byte(source, span.start, span.end, b'{').ok_or(ParseError {
        kind: ParseErrorKind::ExpectedRadarCurve,
        span,
    })?;
    if source.as_bytes().get(span.end.saturating_sub(1)) != Some(&b'}') {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRadarCurve,
            span,
        });
    }
    let (id, label) = parse_radar_labelled_id(
        source,
        Span::new(span.start, open),
        ParseErrorKind::ExpectedRadarCurve,
    )?;
    let values = split_radar_fields(source, open + 1, span.end - 1)?
        .into_iter()
        .map(|value_span| parse_radar_curve_value(source, value_span))
        .collect::<Result<Vec<_>, _>>()?;
    if values.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRadarValue,
            span: Span::new(open + 1, span.end - 1),
        });
    }
    Ok(RadarCurve {
        id,
        label,
        values,
        span,
    })
}

fn parse_radar_curve_value(source: &str, span: Span) -> Result<RadarCurveValue, ParseError> {
    let colon = find_radar_top_level_byte(source, span.start, span.end, b':');
    let (axis, value_start) = if let Some(colon) = colon {
        let axis = parse_radar_id(
            source,
            span.start,
            colon,
            ParseErrorKind::ExpectedRadarValue,
        )?;
        (Some(axis), colon + 1)
    } else {
        (None, span.start)
    };
    let value = parse_radar_number(source, value_start, span.end)?;
    Ok(RadarCurveValue { axis, value, span })
}

fn parse_radar_option(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Option<RadarOption>, ParseError> {
    let keyword_end = source[start..end]
        .find(|value: char| value.is_ascii_whitespace())
        .map_or(end, |offset| start + offset);
    let Some(kind_value) = RadarOptionKind::from_mermaid(&source[start..keyword_end]) else {
        return Ok(None);
    };
    let value_start = skip_ascii_ws(source, keyword_end, end);
    let value = match kind_value {
        RadarOptionKind::ShowLegend => parse_radar_keyword_value(
            source,
            value_start,
            end,
            ParseErrorKind::ExpectedRadarOption,
            &["true", "false"],
        )?,
        RadarOptionKind::Max | RadarOptionKind::Min => {
            parse_radar_number(source, value_start, end)?
        }
        RadarOptionKind::Graticule => parse_radar_keyword_value(
            source,
            value_start,
            end,
            ParseErrorKind::ExpectedRadarOption,
            &["circle", "polygon"],
        )?,
        RadarOptionKind::Ticks => {
            let value = parse_radar_number(source, value_start, end)?;
            if value.value.parse::<u32>().is_err() {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedRadarOption,
                    span: value.span,
                });
            }
            value
        }
    };
    Ok(Some(RadarOption {
        kind: Spanned::new(kind_value, Span::new(start, keyword_end)),
        value,
        span: Span::new(start, end),
    }))
}

fn parse_radar_labelled_id(
    source: &str,
    span: Span,
    kind: ParseErrorKind,
) -> Result<(Spanned<String>, Option<Label>), ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[span.start..span.end]) else {
        return Err(ParseError { kind, span });
    };
    let start = span.start + trim_start;
    let end = span.start + trim_end;
    if let Some(open) = find_radar_top_level_byte(source, start, end, b'[') {
        if source.as_bytes().get(end.saturating_sub(1)) != Some(&b']') {
            return Err(ParseError {
                kind,
                span: Span::new(open, end),
            });
        }
        let id = parse_radar_id(source, start, open, kind)?;
        return Ok((id, Some(label_from_body(source, open + 1, end - 1))));
    }
    Ok((parse_radar_id(source, start, end, kind)?, None))
}

fn parse_radar_id(
    source: &str,
    start: usize,
    end: usize,
    kind: ParseErrorKind,
) -> Result<Spanned<String>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind,
            span: Span::new(start, end),
        });
    };
    let id_start = start + trim_start;
    let id_end = start + trim_end;
    if source[id_start..id_end]
        .chars()
        .any(|value| value.is_ascii_whitespace() || matches!(value, '[' | ']' | '{' | '}' | ','))
    {
        return Err(ParseError {
            kind,
            span: Span::new(id_start, id_end),
        });
    }
    Ok(Spanned::new(
        source[id_start..id_end].to_owned(),
        Span::new(id_start, id_end),
    ))
}

fn parse_radar_number(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<String>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRadarValue,
            span: Span::new(start, end),
        });
    };
    let value_start = start + trim_start;
    let value_end = start + trim_end;
    let value = &source[value_start..value_end];
    if value.parse::<f64>().is_err() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRadarValue,
            span: Span::new(value_start, value_end),
        });
    }
    Ok(Spanned::new(
        value.to_owned(),
        Span::new(value_start, value_end),
    ))
}

fn parse_radar_keyword_value(
    source: &str,
    start: usize,
    end: usize,
    kind: ParseErrorKind,
    allowed: &[&str],
) -> Result<Spanned<String>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind,
            span: Span::new(start, end),
        });
    };
    let value_start = start + trim_start;
    let value_end = start + trim_end;
    let value = &source[value_start..value_end];
    if !allowed.contains(&value) {
        return Err(ParseError {
            kind,
            span: Span::new(value_start, value_end),
        });
    }
    Ok(Spanned::new(
        value.to_owned(),
        Span::new(value_start, value_end),
    ))
}

fn split_radar_fields(source: &str, start: usize, end: usize) -> Result<Vec<Span>, ParseError> {
    let mut fields = Vec::new();
    let mut cursor = start;
    let mut field_start = start;
    let mut quote = None;
    let mut square = 0u16;
    let mut curly = 0u16;
    while cursor < end {
        let byte = source.as_bytes()[cursor];
        if quote == Some(byte) {
            quote = None;
        } else if quote.is_none() && matches!(byte, b'\'' | b'"' | b'`') {
            quote = Some(byte);
        } else if quote.is_none() {
            match byte {
                b'[' => square += 1,
                b']' => square = square.saturating_sub(1),
                b'{' => curly += 1,
                b'}' => curly = curly.saturating_sub(1),
                b',' if square == 0 && curly == 0 => {
                    push_radar_field(source, field_start, cursor, &mut fields);
                    field_start = cursor + 1;
                }
                _ => {}
            }
        }
        cursor += 1;
    }
    if quote.is_some() || square != 0 || curly != 0 {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownRadarStatement,
            span: Span::new(start, end),
        });
    }
    push_radar_field(source, field_start, end, &mut fields);
    Ok(fields)
}

fn push_radar_field(source: &str, start: usize, end: usize, fields: &mut Vec<Span>) {
    if let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) {
        fields.push(Span::new(start + trim_start, start + trim_end));
    }
}

fn find_radar_top_level_byte(source: &str, start: usize, end: usize, target: u8) -> Option<usize> {
    let mut cursor = start;
    let mut quote = None;
    let mut square = 0u16;
    let mut curly = 0u16;
    while cursor < end {
        let byte = source.as_bytes()[cursor];
        if quote == Some(byte) {
            quote = None;
        } else if quote.is_none() && matches!(byte, b'\'' | b'"' | b'`') {
            quote = Some(byte);
        } else if quote.is_none() {
            if byte == target && square == 0 && curly == 0 {
                return Some(cursor);
            }
            match byte {
                b'[' => square += 1,
                b']' => square = square.saturating_sub(1),
                b'{' => curly += 1,
                b'}' => curly = curly.saturating_sub(1),
                _ => {}
            }
        }
        cursor += 1;
    }
    None
}

struct EventModelingStatementParser<'source> {
    source: &'source str,
}

impl<'source> EventModelingStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<EventModelingStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownEventModelingStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(EventModelingStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(EventModelingStatement::Comment(shift_comment(
                comment, start,
            )));
        }
        if has_keyword(self.source, start, "data") {
            return parse_event_modeling_data_block(self.source, start, end)
                .map(|block| EventModelingStatement::DataBlock(Box::new(block)));
        }
        if is_event_modeling_frame_keyword(self.source, start, end) {
            return parse_event_modeling_timeframe(self.source, start, end)
                .map(|frame| EventModelingStatement::TimeFrame(Box::new(frame)));
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownEventModelingStatement,
            span: Span::new(start, end),
        })
    }
}

fn is_event_modeling_frame_keyword(source: &str, start: usize, end: usize) -> bool {
    ["tf", "timeframe", "rf", "resetframe"]
        .iter()
        .any(|keyword| has_exact_keyword(source, start, end, keyword))
}

fn parse_event_modeling_timeframe(
    source: &str,
    start: usize,
    end: usize,
) -> Result<EventModelingTimeFrame, ParseError> {
    let (kind, mut cursor) = parse_event_modeling_frame_kind(source, start, end)?;
    let (number, next) = parse_event_modeling_token(
        source,
        cursor,
        end,
        ParseErrorKind::ExpectedEventModelingFrame,
    )?;
    cursor = next;
    let (entity_type_token, next) = parse_event_modeling_token(
        source,
        cursor,
        end,
        ParseErrorKind::ExpectedEventModelingEntityType,
    )?;
    let Some(entity_type) = EventModelingEntityType::from_mermaid(&entity_type_token.value) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedEventModelingEntityType,
            span: entity_type_token.span,
        });
    };
    cursor = next;
    let (entity, next) = parse_event_modeling_token(
        source,
        cursor,
        end,
        ParseErrorKind::ExpectedEventModelingFrame,
    )?;
    cursor = next;
    let mut data_ref = None;
    let mut data = None;
    let mut relations = Vec::new();

    while cursor < end {
        cursor = skip_ascii_ws(source, cursor, end);
        if cursor >= end {
            break;
        }
        if source[cursor..end].starts_with("[[") {
            let close = source[cursor + 2..end]
                .find("]]")
                .map(|offset| cursor + 2 + offset)
                .ok_or(ParseError {
                    kind: ParseErrorKind::ExpectedEventModelingData,
                    span: Span::new(cursor, end),
                })?;
            let ref_start = cursor + 2;
            let ref_end = close;
            if ref_start == ref_end {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedEventModelingData,
                    span: Span::new(cursor, close + 2),
                });
            }
            data_ref = Some(Spanned::new(
                source[ref_start..ref_end].to_owned(),
                Span::new(ref_start, ref_end),
            ));
            cursor = close + 2;
            continue;
        }
        if matches!(source.as_bytes().get(cursor), Some(b'`' | b'{')) {
            let parsed = parse_event_modeling_data(source, cursor, end)?;
            cursor = parsed.span.end;
            data = Some(parsed);
            continue;
        }
        if source[cursor..end].starts_with("->>") {
            cursor += 3;
            let (target, next) = parse_event_modeling_token(
                source,
                cursor,
                end,
                ParseErrorKind::ExpectedEventModelingFrame,
            )?;
            relations.push(target);
            cursor = next;
            continue;
        }
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedEventModelingFrame,
            span: Span::new(cursor, end),
        });
    }

    Ok(EventModelingTimeFrame {
        kind,
        number,
        entity_type: Spanned::new(entity_type, entity_type_token.span),
        entity,
        data_ref,
        data,
        relations,
        span: Span::new(start, end),
    })
}

fn parse_event_modeling_frame_kind(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(Spanned<EventModelingFrameKind>, usize), ParseError> {
    let keyword_end = source[start..end]
        .find(|value: char| value.is_ascii_whitespace())
        .map_or(end, |offset| start + offset);
    let value = match &source[start..keyword_end] {
        "tf" | "timeframe" => EventModelingFrameKind::TimeFrame,
        "rf" | "resetframe" => EventModelingFrameKind::ResetFrame,
        _ => {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedEventModelingFrame,
                span: Span::new(start, keyword_end),
            });
        }
    };
    Ok((
        Spanned::new(value, Span::new(start, keyword_end)),
        keyword_end,
    ))
}

fn parse_event_modeling_token(
    source: &str,
    start: usize,
    end: usize,
    kind: ParseErrorKind,
) -> Result<(Spanned<String>, usize), ParseError> {
    let token_start = skip_ascii_ws(source, start, end);
    let mut token_end = token_start;
    while token_end < end && !source.as_bytes()[token_end].is_ascii_whitespace() {
        token_end += 1;
    }
    if token_start == token_end {
        return Err(ParseError {
            kind,
            span: Span::new(start, end),
        });
    }
    let value = &source[token_start..token_end];
    if value == "->>" || value.starts_with("[[") || value.starts_with('{') || value.starts_with('`')
    {
        return Err(ParseError {
            kind,
            span: Span::new(token_start, token_end),
        });
    }
    Ok((
        Spanned::new(value.to_owned(), Span::new(token_start, token_end)),
        token_end,
    ))
}

fn parse_event_modeling_data_block(
    source: &str,
    start: usize,
    end: usize,
) -> Result<EventModelingDataBlock, ParseError> {
    let mut cursor = start + "data".len();
    let (id, next) = parse_event_modeling_token(
        source,
        cursor,
        end,
        ParseErrorKind::ExpectedEventModelingData,
    )?;
    cursor = next;
    let data = parse_event_modeling_data(source, cursor, end)?;
    if skip_ascii_ws(source, data.span.end, end) != end {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedEventModelingData,
            span: Span::new(data.span.end, end),
        });
    }
    Ok(EventModelingDataBlock {
        id,
        data,
        span: Span::new(start, end),
    })
}

fn parse_event_modeling_data(
    source: &str,
    start: usize,
    end: usize,
) -> Result<EventModelingData, ParseError> {
    let data_start = skip_ascii_ws(source, start, end);
    let mut cursor = data_start;
    let mut ty = None;
    if source.as_bytes().get(cursor) == Some(&b'`') {
        let ty_end = source[cursor + 1..end]
            .find('`')
            .map(|offset| cursor + 1 + offset)
            .ok_or(ParseError {
                kind: ParseErrorKind::ExpectedEventModelingData,
                span: Span::new(cursor, end),
            })?;
        if cursor + 1 == ty_end {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedEventModelingData,
                span: Span::new(cursor, ty_end + 1),
            });
        }
        ty = Some(Spanned::new(
            source[cursor + 1..ty_end].to_owned(),
            Span::new(cursor + 1, ty_end),
        ));
        cursor = skip_ascii_ws(source, ty_end + 1, end);
    }
    if source.as_bytes().get(cursor) != Some(&b'{') {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedEventModelingData,
            span: Span::new(cursor, end),
        });
    }
    let close = find_event_modeling_data_close(source, cursor, end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedEventModelingData,
        span: Span::new(cursor, end),
    })?;
    Ok(EventModelingData {
        ty,
        body: label_from_body(source, cursor + 1, close),
        span: Span::new(data_start, close + 1),
    })
}

fn find_event_modeling_data_close(source: &str, open: usize, end: usize) -> Option<usize> {
    let mut cursor = open;
    let mut quote = None;
    let mut curly = 0u16;
    while cursor < end {
        let byte = source.as_bytes()[cursor];
        if quote == Some(byte) {
            quote = None;
        } else if quote.is_none() && matches!(byte, b'\'' | b'"' | b'`') {
            quote = Some(byte);
        } else if quote.is_none() {
            match byte {
                b'{' => curly += 1,
                b'}' => {
                    curly = curly.saturating_sub(1);
                    if curly == 0 {
                        return Some(cursor);
                    }
                }
                _ => {}
            }
        }
        cursor += 1;
    }
    None
}

struct TreemapStatementParser<'source> {
    source: &'source str,
}

impl<'source> TreemapStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<TreemapStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownTreemapStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(TreemapStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(TreemapStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "classDef") {
            let class_def = shift_class_def(
                Parser::parse_flow_class_def(trimmed).map_err(|error| shift_error(error, start))?,
                start,
            );
            return Ok(TreemapStatement::ClassDef(class_def));
        }
        parse_treemap_node(&self.source[start..end])
            .map(|node| TreemapStatement::Node(Box::new(shift_treemap_node(node, start))))
            .map_err(|error| shift_error(error, start))
    }
}

struct VennStatementParser<'source> {
    source: &'source str,
}

impl<'source> VennStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<VennStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownVennStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(VennStatement::Directive(shift_directive(directive, start)));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(VennStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "title") {
            let label_start = skip_ascii_ws(self.source, start + "title".len(), end);
            let label = label_from_trimmed(self.source, label_start, end).ok_or(ParseError {
                kind: ParseErrorKind::UnknownVennStatement,
                span: Span::new(start, end),
            })?;
            return Ok(VennStatement::Title(label));
        }
        if has_keyword(self.source, start, "set") {
            return parse_venn_set(self.source, start, end)
                .map(|set| VennStatement::Set(Box::new(set)));
        }
        if has_keyword(self.source, start, "union") {
            return parse_venn_union(self.source, start, end)
                .map(|union| VennStatement::Union(Box::new(union)));
        }
        if has_keyword(self.source, start, "text") {
            return parse_venn_text(self.source, start, end)
                .map(|text| VennStatement::Text(Box::new(text)));
        }
        if has_keyword(self.source, start, "style") {
            return parse_venn_style(self.source, start, end).map(VennStatement::Style);
        }
        Err(ParseError {
            kind: ParseErrorKind::UnknownVennStatement,
            span: Span::new(start, end),
        })
    }
}

fn parse_venn_set(source: &str, start: usize, end: usize) -> Result<VennSet, ParseError> {
    let cursor = start + "set".len();
    let (id, cursor) = parse_venn_identifier(source, cursor, end, ParseErrorKind::ExpectedVennSet)?;
    let (label, size, cursor) =
        parse_venn_label_size(source, cursor, end, ParseErrorKind::ExpectedVennSet)?;
    if cursor != end {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedVennSet,
            span: Span::new(cursor, end),
        });
    }
    Ok(VennSet {
        id,
        label,
        size,
        texts: Vec::new(),
        span: Span::new(start, end),
    })
}

fn parse_venn_union(source: &str, start: usize, end: usize) -> Result<VennUnion, ParseError> {
    let mut cursor = start + "union".len();
    let mut members = Vec::new();
    loop {
        let (member, next) =
            parse_venn_identifier(source, cursor, end, ParseErrorKind::ExpectedVennUnion)?;
        members.push(member);
        cursor = skip_ascii_ws(source, next, end);
        if source.as_bytes().get(cursor) != Some(&b',') {
            break;
        }
        cursor += 1;
    }
    if members.len() < 2 {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedVennUnion,
            span: Span::new(start, end),
        });
    }
    let (label, size, cursor) =
        parse_venn_label_size(source, cursor, end, ParseErrorKind::ExpectedVennUnion)?;
    if cursor != end {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedVennUnion,
            span: Span::new(cursor, end),
        });
    }
    Ok(VennUnion {
        members,
        label,
        size,
        texts: Vec::new(),
        span: Span::new(start, end),
    })
}

fn parse_venn_text(source: &str, start: usize, end: usize) -> Result<VennText, ParseError> {
    let cursor = start + "text".len();
    let (id, cursor) =
        parse_venn_identifier(source, cursor, end, ParseErrorKind::ExpectedVennText)?;
    let (label, size, cursor) =
        parse_venn_label_size(source, cursor, end, ParseErrorKind::ExpectedVennText)?;
    if size.is_some() || cursor != end {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedVennText,
            span: Span::new(cursor, end),
        });
    }
    Ok(VennText {
        id,
        label,
        owner: None,
        span: Span::new(start, end),
    })
}

fn parse_venn_style(source: &str, start: usize, end: usize) -> Result<VennStyle, ParseError> {
    let target_start = skip_ascii_ws(source, start + "style".len(), end);
    let target_end = source[target_start..end]
        .find(|value: char| value.is_ascii_whitespace())
        .map_or(end, |offset| target_start + offset);
    let targets = parse_csv_identifiers(
        source,
        target_start,
        target_end,
        ParseErrorKind::ExpectedVennStyle,
    )?;
    let declaration_start = skip_ascii_ws(source, target_end, end);
    let declarations = parse_style_declarations(source, declaration_start, end)?;
    Ok(VennStyle {
        targets,
        declarations,
        span: Span::new(start, end),
    })
}

fn parse_venn_identifier(
    source: &str,
    start: usize,
    end: usize,
    kind: ParseErrorKind,
) -> Result<(Spanned<String>, usize), ParseError> {
    let start = skip_ascii_ws(source, start, end);
    if start >= end {
        return Err(ParseError {
            kind,
            span: Span::new(start, end),
        });
    }
    if source.as_bytes().get(start) == Some(&b'"') {
        let close = find_treemap_quote_end(source, start + 1, end).ok_or(ParseError {
            kind,
            span: Span::new(start, end),
        })?;
        return Ok((
            Spanned::new(
                source[start + 1..close].to_owned(),
                Span::new(start + 1, close),
            ),
            close + 1,
        ));
    }
    let mut cursor = start;
    while cursor < end
        && !source.as_bytes()[cursor].is_ascii_whitespace()
        && !matches!(source.as_bytes()[cursor], b',' | b'[' | b':' | b']')
    {
        cursor += 1;
    }
    if cursor == start {
        return Err(ParseError {
            kind,
            span: Span::new(start, end),
        });
    }
    Ok((
        Spanned::new(source[start..cursor].to_owned(), Span::new(start, cursor)),
        cursor,
    ))
}

fn parse_venn_label_size(
    source: &str,
    start: usize,
    end: usize,
    kind: ParseErrorKind,
) -> Result<(Option<Label>, Option<Spanned<String>>, usize), ParseError> {
    let mut cursor = skip_ascii_ws(source, start, end);
    let mut label = None;
    if source.as_bytes().get(cursor) == Some(&b'[') {
        let close = source[cursor + 1..end]
            .find(']')
            .map(|offset| cursor + 1 + offset)
            .ok_or(ParseError {
                kind,
                span: Span::new(cursor, end),
            })?;
        label = Some(label_from_body(source, cursor + 1, close));
        cursor = skip_ascii_ws(source, close + 1, end);
    }
    let mut size = None;
    if source.as_bytes().get(cursor) == Some(&b':') {
        let value_start = skip_ascii_ws(source, cursor + 1, end);
        let value_end = source[value_start..end]
            .find(|value: char| value.is_ascii_whitespace())
            .map_or(end, |offset| value_start + offset);
        size = Some(parse_venn_value(source, value_start, value_end)?);
        cursor = skip_ascii_ws(source, value_end, end);
    }
    Ok((label, size, cursor))
}

fn parse_venn_value(source: &str, start: usize, end: usize) -> Result<Spanned<String>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedVennValue,
            span: Span::new(start, end),
        });
    };
    let value_start = start + trim_start;
    let value_end = start + trim_end;
    let value = &source[value_start..value_end];
    let parsed = value.parse::<f64>().map_err(|_| ParseError {
        kind: ParseErrorKind::ExpectedVennValue,
        span: Span::new(value_start, value_end),
    })?;
    if !parsed.is_finite() || parsed < 0.0 {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedVennValue,
            span: Span::new(value_start, value_end),
        });
    }
    Ok(Spanned::new(
        value.to_owned(),
        Span::new(value_start, value_end),
    ))
}

struct IshikawaStatementParser<'source> {
    source: &'source str,
}

impl<'source> IshikawaStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<IshikawaStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownIshikawaStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(IshikawaStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(IshikawaStatement::Comment(shift_comment(comment, start)));
        }
        parse_ishikawa_node(trimmed, start)
            .map(|node| IshikawaStatement::Cause(Box::new(node)))
            .map_err(|_| ParseError {
                kind: ParseErrorKind::UnknownIshikawaStatement,
                span: Span::new(start, end),
            })
    }
}

fn parse_ishikawa_node(source: &str, offset: usize) -> Result<IshikawaNode, ParseError> {
    let label = parse_ishikawa_label(source, offset, ParseErrorKind::ExpectedIshikawaCause)?;
    Ok(IshikawaNode {
        span: label.span,
        label,
        causes: Vec::new(),
    })
}

fn parse_ishikawa_label(
    source: &str,
    offset: usize,
    kind: ParseErrorKind,
) -> Result<Label, ParseError> {
    label_from_trimmed(source, 0, source.len())
        .map(|label| shift_label(label, offset))
        .ok_or(ParseError {
            kind,
            span: Span::new(offset, offset + source.len()),
        })
}

struct ParsedIshikawaNode {
    node: IshikawaNode,
    children: Vec<usize>,
}

fn build_ishikawa_node(index: usize, parsed: &[ParsedIshikawaNode]) -> IshikawaNode {
    let parsed_node = &parsed[index];
    let mut node = parsed_node.node.clone();
    node.causes = parsed_node
        .children
        .iter()
        .map(|child| build_ishikawa_node(*child, parsed))
        .collect();
    node
}

struct WardleyStatementParser<'source> {
    source: &'source str,
}

impl<'source> WardleyStatementParser<'source> {
    fn new(source: &'source str) -> Self {
        Self {
            source: first_line(source),
        }
    }

    fn parse(&self) -> Result<WardleyStatement, ParseError> {
        let Some((start, end)) = trimmed_statement_bounds(self.source) else {
            return Err(ParseError {
                kind: ParseErrorKind::UnknownWardleyStatement,
                span: Span::new(0, 0),
            });
        };
        let trimmed = &self.source[start..end];
        if let Ok(directive) = Parser::parse_mermaid_directive(trimmed) {
            return Ok(WardleyStatement::Directive(shift_directive(
                directive, start,
            )));
        }
        if let Ok(comment) = Parser::parse_mermaid_comment(trimmed) {
            return Ok(WardleyStatement::Comment(shift_comment(comment, start)));
        }
        if has_keyword(self.source, start, "title") {
            let label_start = skip_ascii_ws(self.source, start + "title".len(), end);
            let label = label_from_trimmed(self.source, label_start, end).ok_or(ParseError {
                kind: ParseErrorKind::UnknownWardleyStatement,
                span: Span::new(start, end),
            })?;
            return Ok(WardleyStatement::Title(label));
        }
        if has_keyword(self.source, start, "size") {
            return parse_wardley_size(self.source, start, end).map(WardleyStatement::Size);
        }
        if has_keyword(self.source, start, "component") {
            return parse_wardley_component(
                self.source,
                start,
                end,
                WardleyComponentKind::Component,
                false,
            )
            .map(|component| WardleyStatement::Component(Box::new(component)));
        }
        if has_keyword(self.source, start, "anchor") {
            return parse_wardley_component(
                self.source,
                start,
                end,
                WardleyComponentKind::Anchor,
                false,
            )
            .map(|component| WardleyStatement::Component(Box::new(component)));
        }
        if has_keyword(self.source, start, "pipeline") {
            return wardley_pipeline_start(self.source, start)?
                .map(WardleyStatement::Pipeline)
                .ok_or(ParseError {
                    kind: ParseErrorKind::UnknownWardleyStatement,
                    span: Span::new(start, end),
                });
        }
        if has_keyword(self.source, start, "evolve") {
            return parse_wardley_evolve(self.source, start, end).map(WardleyStatement::Evolve);
        }
        if has_keyword(self.source, start, "note") {
            return parse_wardley_note(self.source, start, end).map(WardleyStatement::Note);
        }
        if has_keyword(self.source, start, "annotations") {
            return parse_wardley_annotations(self.source, start, end)
                .map(WardleyStatement::Annotations);
        }
        if has_keyword(self.source, start, "annotation") {
            return parse_wardley_annotation(self.source, start, end)
                .map(WardleyStatement::Annotation);
        }
        if has_keyword(self.source, start, "accelerator") {
            return parse_wardley_force(self.source, start, end, WardleyForceKind::Accelerator)
                .map(WardleyStatement::Force);
        }
        if has_keyword(self.source, start, "deaccelerator") {
            return parse_wardley_force(self.source, start, end, WardleyForceKind::Deaccelerator)
                .map(WardleyStatement::Force);
        }
        if has_keyword(self.source, start, "evolution") {
            return parse_wardley_evolution(self.source, start, end)
                .map(WardleyStatement::Evolution);
        }
        parse_wardley_link(self.source, start, end).map(WardleyStatement::Link)
    }
}

fn parse_wardley_size(source: &str, start: usize, end: usize) -> Result<WardleySize, ParseError> {
    let cursor = skip_ascii_ws(source, start + "size".len(), end);
    let (values, span, cursor) = parse_wardley_bracket_values(source, cursor, end, 2)?;
    if cursor != end {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedWardleyValue,
            span: Span::new(cursor, end),
        });
    }
    let width = values[0]
        .value
        .parse::<u32>()
        .map_err(|_| wardley_value_error(values[0].span))?;
    let height = values[1]
        .value
        .parse::<u32>()
        .map_err(|_| wardley_value_error(values[1].span))?;
    Ok(WardleySize {
        width,
        height,
        span,
    })
}

fn parse_wardley_component(
    source: &str,
    start: usize,
    end: usize,
    kind: WardleyComponentKind,
    pipeline_component: bool,
) -> Result<WardleyComponent, ParseError> {
    let keyword = if kind == WardleyComponentKind::Anchor {
        "anchor"
    } else {
        "component"
    };
    let name_start = skip_ascii_ws(source, start + keyword.len(), end);
    let coord_open = source[name_start..end]
        .find('[')
        .map(|offset| name_start + offset)
        .ok_or(ParseError {
            kind: ParseErrorKind::ExpectedWardleyCoord,
            span: Span::new(name_start, end),
        })?;
    let name = wardley_name_label(source, name_start, coord_open)?;
    let (coord, mut cursor) = if pipeline_component {
        parse_wardley_pipeline_coord(source, coord_open, end)?
    } else {
        parse_wardley_coord(source, coord_open, end)?
    };
    let mut label_offset = None;
    let mut decorators = Vec::new();
    loop {
        cursor = skip_ascii_ws(source, cursor, end);
        if cursor == end {
            break;
        }
        if has_keyword(source, cursor, "label") {
            let next = skip_ascii_ws(source, cursor + "label".len(), end);
            let (offset, after) = parse_wardley_label_offset(source, next, end)?;
            label_offset = Some(offset);
            cursor = after;
            continue;
        }
        if source.as_bytes().get(cursor) == Some(&b'(') {
            let close = source[cursor + 1..end]
                .find(')')
                .map(|offset| cursor + 1 + offset)
                .ok_or(ParseError {
                    kind: ParseErrorKind::ExpectedWardleyDecorator,
                    span: Span::new(cursor, end),
                })?;
            decorators.push(parse_wardley_decorator(
                &source[cursor + 1..close],
                cursor + 1,
            )?);
            cursor = close + 1;
            continue;
        }
        return Err(ParseError {
            kind: ParseErrorKind::UnknownWardleyStatement,
            span: Span::new(cursor, end),
        });
    }
    Ok(WardleyComponent {
        kind,
        name,
        coord,
        label_offset,
        decorators,
        pipeline: None,
        span: Span::new(start, end),
    })
}

fn parse_wardley_evolve(
    source: &str,
    start: usize,
    end: usize,
) -> Result<WardleyEvolve, ParseError> {
    let body_start = skip_ascii_ws(source, start + "evolve".len(), end);
    let value_start = source[..end]
        .rfind(char::is_whitespace)
        .map(|index| skip_ascii_ws(source, index, end))
        .filter(|index| *index > body_start)
        .ok_or(ParseError {
            kind: ParseErrorKind::ExpectedWardleyValue,
            span: Span::new(body_start, end),
        })?;
    let name = wardley_name_label(source, body_start, value_start)?;
    let value = parse_wardley_scalar(source, value_start, end)?;
    Ok(WardleyEvolve {
        name,
        target_evolution: value,
        span: Span::new(start, end),
    })
}

fn parse_wardley_note(source: &str, start: usize, end: usize) -> Result<WardleyNote, ParseError> {
    let cursor = skip_ascii_ws(source, start + "note".len(), end);
    let (text, cursor) = parse_wardley_quoted_label(source, cursor, end)?;
    let cursor = skip_ascii_ws(source, cursor, end);
    let (coord, cursor) = parse_wardley_coord(source, cursor, end)?;
    if cursor != end {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownWardleyStatement,
            span: Span::new(cursor, end),
        });
    }
    Ok(WardleyNote {
        text,
        coord,
        span: Span::new(start, end),
    })
}

fn parse_wardley_annotations(
    source: &str,
    start: usize,
    end: usize,
) -> Result<WardleyCoord, ParseError> {
    let cursor = skip_ascii_ws(source, start + "annotations".len(), end);
    let (coord, cursor) = parse_wardley_coord(source, cursor, end)?;
    if cursor != end {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownWardleyStatement,
            span: Span::new(cursor, end),
        });
    }
    Ok(coord)
}

fn parse_wardley_annotation(
    source: &str,
    start: usize,
    end: usize,
) -> Result<WardleyAnnotation, ParseError> {
    let mut cursor = skip_ascii_ws(source, start + "annotation".len(), end);
    let number_start = cursor;
    while cursor < end && source.as_bytes()[cursor].is_ascii_digit() {
        cursor += 1;
    }
    if cursor == number_start || source.as_bytes().get(cursor) != Some(&b',') {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedWardleyValue,
            span: Span::new(number_start, end),
        });
    }
    let number = Spanned::new(
        source[number_start..cursor].to_owned(),
        Span::new(number_start, cursor),
    );
    cursor = skip_ascii_ws(source, cursor + 1, end);
    let (coord, cursor_after_coord) = parse_wardley_coord(source, cursor, end)?;
    cursor = skip_ascii_ws(source, cursor_after_coord, end);
    let (text, cursor) = parse_wardley_quoted_label(source, cursor, end)?;
    if skip_ascii_ws(source, cursor, end) != end {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownWardleyStatement,
            span: Span::new(cursor, end),
        });
    }
    Ok(WardleyAnnotation {
        number,
        coord,
        text,
        span: Span::new(start, end),
    })
}

fn parse_wardley_force(
    source: &str,
    start: usize,
    end: usize,
    kind: WardleyForceKind,
) -> Result<WardleyForce, ParseError> {
    let keyword = match kind {
        WardleyForceKind::Accelerator => "accelerator",
        WardleyForceKind::Deaccelerator => "deaccelerator",
    };
    let cursor = skip_ascii_ws(source, start + keyword.len(), end);
    let (text, cursor) = parse_wardley_quoted_label(source, cursor, end)?;
    let cursor = skip_ascii_ws(source, cursor, end);
    let (coord, cursor) = parse_wardley_coord(source, cursor, end)?;
    if cursor != end {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownWardleyStatement,
            span: Span::new(cursor, end),
        });
    }
    Ok(WardleyForce {
        kind,
        text,
        coord,
        span: Span::new(start, end),
    })
}

fn parse_wardley_evolution(
    source: &str,
    start: usize,
    end: usize,
) -> Result<WardleyEvolution, ParseError> {
    let body_start = skip_ascii_ws(source, start + "evolution".len(), end);
    let mut stages = Vec::new();
    let mut cursor = body_start;
    for raw in source[body_start..end].split("->") {
        let stage_start = cursor;
        let stage_end = cursor + raw.len();
        let label = wardley_evolution_stage(source, stage_start, stage_end)?;
        stages.push(label);
        cursor = stage_end + 2;
    }
    if stages.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedWardleyName,
            span: Span::new(body_start, end),
        });
    }
    Ok(WardleyEvolution {
        stages,
        span: Span::new(start, end),
    })
}

fn wardley_evolution_stage(
    source: &str,
    start: usize,
    end: usize,
) -> Result<WardleyEvolutionStage, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedWardleyName,
            span: Span::new(start, end),
        });
    };
    let stage_start = start + trim_start;
    let stage_end = start + trim_end;
    let at = source[stage_start..stage_end]
        .rfind('@')
        .map(|offset| stage_start + offset);
    let (label_end, boundary) = if let Some(at) = at {
        let boundary = parse_wardley_scalar(source, at + 1, stage_end)?;
        (at, Some(boundary))
    } else {
        (stage_end, None)
    };
    Ok(WardleyEvolutionStage {
        label: wardley_name_label(source, stage_start, label_end)?,
        boundary,
        span: Span::new(stage_start, stage_end),
    })
}

fn parse_wardley_link(source: &str, start: usize, end: usize) -> Result<WardleyLink, ParseError> {
    if let Some(open) = source[start..end].find("+'").map(|offset| start + offset) {
        let close = source[open + 2..end]
            .find("'>")
            .map(|offset| open + 2 + offset)
            .ok_or(ParseError {
                kind: ParseErrorKind::ExpectedWardleyLink,
                span: Span::new(open, end),
            })?;
        let from = wardley_name_label(source, start, open)?;
        let label = Some(label_from_body(source, open + 2, close));
        let to = wardley_name_label(source, close + 2, end)?;
        return Ok(WardleyLink {
            from,
            to,
            kind: WardleyLinkKind::Flow,
            label,
            span: Span::new(start, end),
        });
    }
    const OPERATORS: [(&str, WardleyLinkKind); 6] = [
        ("+<>", WardleyLinkKind::BidirectionalFlow),
        ("-.->", WardleyLinkKind::Dashed),
        ("-->", WardleyLinkKind::Dependency),
        ("+>", WardleyLinkKind::Flow),
        ("+<", WardleyLinkKind::ReverseFlow),
        ("->", WardleyLinkKind::Dependency),
    ];
    let (body_end, label) = if let Some(index) = source[start..end].find(';') {
        let semicolon = start + index;
        (semicolon, label_from_trimmed(source, semicolon + 1, end))
    } else {
        (end, None)
    };
    for (operator, kind) in OPERATORS {
        if let Some(index) = source[start..body_end].find(operator) {
            let operator_start = start + index;
            let from = wardley_name_label(source, start, operator_start)?;
            let to = wardley_name_label(source, operator_start + operator.len(), body_end)?;
            return Ok(WardleyLink {
                from,
                to,
                kind,
                label,
                span: Span::new(start, end),
            });
        }
    }
    Err(ParseError {
        kind: ParseErrorKind::UnknownWardleyStatement,
        span: Span::new(start, end),
    })
}

fn wardley_pipeline_start(source: &str, offset: usize) -> Result<Option<Label>, ParseError> {
    let Some((start, end)) = trimmed_statement_bounds(source) else {
        return Ok(None);
    };
    if !has_keyword(source, start, "pipeline") {
        return Ok(None);
    }
    let body_start = skip_ascii_ws(source, start + "pipeline".len(), end);
    if source.as_bytes().get(end.saturating_sub(1)) != Some(&b'{') {
        return Err(ParseError {
            kind: ParseErrorKind::UnknownWardleyStatement,
            span: Span::new(offset + start, offset + end),
        });
    }
    let label = wardley_name_label(source, body_start, end - 1)?;
    Ok(Some(shift_label(label, offset)))
}

fn parse_wardley_coord(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(WardleyCoord, usize), ParseError> {
    let (values, span, cursor) = parse_wardley_bracket_values(source, start, end, 2)?;
    validate_wardley_scalar(&values[0])?;
    validate_wardley_scalar(&values[1])?;
    Ok((
        WardleyCoord {
            visibility: values[0].clone(),
            evolution: values[1].clone(),
            span,
        },
        cursor,
    ))
}

fn parse_wardley_pipeline_coord(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(WardleyCoord, usize), ParseError> {
    let (values, span, cursor) = parse_wardley_bracket_values(source, start, end, 1)?;
    validate_wardley_scalar(&values[0])?;
    Ok((
        WardleyCoord {
            visibility: Spanned::new("0.5".to_owned(), values[0].span),
            evolution: values[0].clone(),
            span,
        },
        cursor,
    ))
}

fn parse_wardley_label_offset(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(WardleyLabelOffset, usize), ParseError> {
    let (values, span, cursor) = parse_wardley_bracket_values(source, start, end, 2)?;
    let x = values[0]
        .value
        .parse::<i32>()
        .map_err(|_| wardley_value_error(values[0].span))?;
    let y = values[1]
        .value
        .parse::<i32>()
        .map_err(|_| wardley_value_error(values[1].span))?;
    Ok((WardleyLabelOffset { x, y, span }, cursor))
}

fn parse_wardley_bracket_values(
    source: &str,
    start: usize,
    end: usize,
    expected: usize,
) -> Result<(Vec<Spanned<String>>, Span, usize), ParseError> {
    let start = skip_ascii_ws(source, start, end);
    if source.as_bytes().get(start) != Some(&b'[') {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedWardleyCoord,
            span: Span::new(start, end),
        });
    }
    let close = source[start + 1..end]
        .find(']')
        .map(|offset| start + 1 + offset)
        .ok_or(ParseError {
            kind: ParseErrorKind::ExpectedWardleyCoord,
            span: Span::new(start, end),
        })?;
    let mut values = Vec::new();
    let mut cursor = start + 1;
    for raw in source[start + 1..close].split(',') {
        let value_start = cursor;
        let value_end = cursor + raw.len();
        values.push(parse_wardley_scalar(source, value_start, value_end)?);
        cursor = value_end + 1;
    }
    if values.len() != expected {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedWardleyCoord,
            span: Span::new(start, close + 1),
        });
    }
    Ok((
        values,
        Span::new(start, close + 1),
        skip_ascii_ws(source, close + 1, end),
    ))
}

fn parse_wardley_scalar(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<String>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(wardley_value_error(Span::new(start, end)));
    };
    let value_start = start + trim_start;
    let value_end = start + trim_end;
    let value = &source[value_start..value_end];
    let parsed = value
        .parse::<f64>()
        .map_err(|_| wardley_value_error(Span::new(value_start, value_end)))?;
    if !parsed.is_finite() {
        return Err(wardley_value_error(Span::new(value_start, value_end)));
    }
    Ok(Spanned::new(
        value.to_owned(),
        Span::new(value_start, value_end),
    ))
}

fn validate_wardley_scalar(value: &Spanned<String>) -> Result<(), ParseError> {
    let parsed = value
        .value
        .parse::<f64>()
        .map_err(|_| wardley_value_error(value.span))?;
    if !(0.0..=1.0).contains(&parsed) {
        return Err(wardley_value_error(value.span));
    }
    Ok(())
}

fn wardley_value_error(span: Span) -> ParseError {
    ParseError {
        kind: ParseErrorKind::ExpectedWardleyValue,
        span,
    }
}

fn wardley_name_label(source: &str, start: usize, end: usize) -> Result<Label, ParseError> {
    label_from_trimmed(source, start, end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedWardleyName,
        span: Span::new(start, end),
    })
}

fn parse_wardley_quoted_label(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(Label, usize), ParseError> {
    let start = skip_ascii_ws(source, start, end);
    if source.as_bytes().get(start) != Some(&b'"') {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedWardleyName,
            span: Span::new(start, end),
        });
    }
    let close = find_treemap_quote_end(source, start + 1, end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedWardleyName,
        span: Span::new(start, end),
    })?;
    Ok((label_from_body(source, start, close + 1), close + 1))
}

fn parse_wardley_decorator(source: &str, offset: usize) -> Result<WardleyDecorator, ParseError> {
    match source.trim() {
        "inertia" => Ok(WardleyDecorator::Inertia),
        "build" => Ok(WardleyDecorator::Build),
        "buy" => Ok(WardleyDecorator::Buy),
        "outsource" => Ok(WardleyDecorator::Outsource),
        "market" => Ok(WardleyDecorator::Market),
        _ => Err(ParseError {
            kind: ParseErrorKind::ExpectedWardleyDecorator,
            span: Span::new(offset, offset + source.len()),
        }),
    }
}

fn parse_sankey_link(source: &str, start: usize, end: usize) -> Result<SankeyLink, ParseError> {
    let fields = parse_sankey_csv_fields(source, start, end)?;
    let [source_field, target_field, value_field] = fields.as_slice() else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedSankeyLink,
            span: Span::new(start, end),
        });
    };
    let source_label =
        label_from_trimmed(source, source_field.start, source_field.end).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedSankeyLink,
            span: Span::new(source_field.start, source_field.end),
        })?;
    let target_label =
        label_from_trimmed(source, target_field.start, target_field.end).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedSankeyLink,
            span: Span::new(target_field.start, target_field.end),
        })?;
    let (value_units, value_text) = parse_sankey_value(source, value_field.start, value_field.end)?;
    Ok(SankeyLink {
        source: source_label,
        target: target_label,
        value_units,
        value_text,
        span: Span::new(start, end),
    })
}

#[derive(Debug, Clone, Copy)]
struct SankeyCsvField {
    start: usize,
    end: usize,
}

fn parse_sankey_csv_fields(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<SankeyCsvField>, ParseError> {
    let mut fields = Vec::new();
    let mut cursor = start;
    let mut field_start = start;
    let mut quote = false;
    let bytes = source.as_bytes();
    while cursor < end {
        match bytes[cursor] {
            b'"' if quote && bytes.get(cursor + 1) == Some(&b'"') => {
                cursor += 2;
                continue;
            }
            b'"' => quote = !quote,
            b',' if !quote => {
                fields.push(SankeyCsvField {
                    start: field_start,
                    end: cursor,
                });
                field_start = cursor + 1;
            }
            _ => {}
        }
        cursor += 1;
    }
    if quote {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedSankeyLink,
            span: Span::new(start, end),
        });
    }
    fields.push(SankeyCsvField {
        start: field_start,
        end,
    });
    Ok(fields)
}

fn parse_sankey_value(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(Spanned<u64>, Spanned<String>), ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedSankeyValue,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let raw = &source[absolute_start..absolute_end];
    let Some(units) = parse_sankey_value_units(raw) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedSankeyValue,
            span: Span::new(absolute_start, absolute_end),
        });
    };
    Ok((
        Spanned::new(units, Span::new(absolute_start, absolute_end)),
        Spanned::new(raw.to_owned(), Span::new(absolute_start, absolute_end)),
    ))
}

fn parse_sankey_value_units(value: &str) -> Option<u64> {
    let parsed = value.parse::<f64>().ok()?;
    if !parsed.is_finite() || parsed <= 0.0 {
        return None;
    }
    Some((parsed * 100.0).round() as u64)
}

fn parse_xy_chart_axis(
    source: &str,
    start: usize,
    end: usize,
    keyword: &str,
    kind: XyChartAxisKind,
) -> Result<XyChartAxis, ParseError> {
    let rest_start = start + keyword.len();
    let mut title_end = end;
    let mut scale = None;
    if let Some(bracket_start) = source[rest_start..end].find('[') {
        let bracket_start = rest_start + bracket_start;
        let bracket_end = source[bracket_start..end]
            .rfind(']')
            .map(|offset| bracket_start + offset)
            .ok_or(ParseError {
                kind: ParseErrorKind::ExpectedXyChartAxis,
                span: Span::new(bracket_start, end),
            })?;
        title_end = bracket_start;
        scale = Some(XyChartAxisScale::Categories(parse_xy_chart_categories(
            source,
            bracket_start + 1,
            bracket_end,
        )?));
    } else if let Some(arrow) = source[rest_start..end].find("-->") {
        let arrow = rest_start + arrow;
        let left = source[rest_start..arrow].trim_end();
        let min_start = rest_start
            + left
                .rfind(|value: char| value.is_ascii_whitespace())
                .map_or(0, |offset| offset + 1);
        let min = parse_xy_chart_value(source, min_start, arrow)?;
        let max = parse_xy_chart_value(source, arrow + "-->".len(), end)?;
        title_end = min_start;
        scale = Some(XyChartAxisScale::Range { min, max });
    }
    let title = label_from_trimmed(source, rest_start, title_end);
    Ok(XyChartAxis {
        kind: Spanned::new(kind, Span::new(start, start + keyword.len())),
        title,
        scale,
        span: Span::new(start, end),
    })
}

fn parse_xy_chart_series(
    source: &str,
    start: usize,
    end: usize,
    keyword: &str,
    kind: XyChartSeriesKind,
) -> Result<XyChartSeries, ParseError> {
    let values_start = source[start + keyword.len()..end]
        .find('[')
        .map(|offset| start + keyword.len() + offset)
        .ok_or(ParseError {
            kind: ParseErrorKind::ExpectedXyChartSeries,
            span: Span::new(start, end),
        })?;
    let values_end = source[values_start..end]
        .rfind(']')
        .map(|offset| values_start + offset)
        .ok_or(ParseError {
            kind: ParseErrorKind::ExpectedXyChartSeries,
            span: Span::new(values_start, end),
        })?;
    let mut values = Vec::new();
    let mut value_texts = Vec::new();
    for field in parse_sankey_csv_fields(source, values_start + 1, values_end)? {
        let (value, text) = parse_xy_chart_value_with_text(source, field.start, field.end)?;
        values.push(value);
        value_texts.push(text);
    }
    if values.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedXyChartSeries,
            span: Span::new(values_start, values_end),
        });
    }
    Ok(XyChartSeries {
        kind: Spanned::new(kind, Span::new(start, start + keyword.len())),
        values,
        value_texts,
        span: Span::new(start, end),
    })
}

fn parse_xy_chart_categories(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<Label>, ParseError> {
    let mut labels = Vec::new();
    for field in parse_sankey_csv_fields(source, start, end)? {
        let label = label_from_trimmed(source, field.start, field.end).ok_or(ParseError {
            kind: ParseErrorKind::ExpectedXyChartAxis,
            span: Span::new(field.start, field.end),
        })?;
        labels.push(label);
    }
    Ok(labels)
}

fn parse_xy_chart_value(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<i64>, ParseError> {
    parse_xy_chart_value_with_text(source, start, end).map(|(value, _)| value)
}

fn parse_xy_chart_value_with_text(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(Spanned<i64>, Spanned<String>), ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedXyChartValue,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let raw = &source[absolute_start..absolute_end];
    let Ok(parsed) = raw.parse::<f64>() else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedXyChartValue,
            span: Span::new(absolute_start, absolute_end),
        });
    };
    if !parsed.is_finite() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedXyChartValue,
            span: Span::new(absolute_start, absolute_end),
        });
    }
    Ok((
        Spanned::new(
            (parsed * 100.0).round() as i64,
            Span::new(absolute_start, absolute_end),
        ),
        Spanned::new(raw.to_owned(), Span::new(absolute_start, absolute_end)),
    ))
}

fn zenuml_fragment_keyword(source: &str) -> Option<(&'static str, ZenUmlFragmentKind)> {
    const KEYWORDS: [(&str, ZenUmlFragmentKind); 9] = [
        ("while", ZenUmlFragmentKind::Loop),
        ("for", ZenUmlFragmentKind::Loop),
        ("if", ZenUmlFragmentKind::Alt),
        ("else", ZenUmlFragmentKind::Alt),
        ("opt", ZenUmlFragmentKind::Opt),
        ("par", ZenUmlFragmentKind::Parallel),
        ("try", ZenUmlFragmentKind::Try),
        ("catch", ZenUmlFragmentKind::Catch),
        ("finally", ZenUmlFragmentKind::Finally),
    ];
    KEYWORDS
        .into_iter()
        .find(|(keyword, _)| source == *keyword || source.starts_with(&format!("{keyword} ")))
}

fn parse_zenuml_target(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<String>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedZenUmlMessage,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let trimmed_end = start + trim_end;
    let absolute_end = zenuml_target_end(source, absolute_start, trimmed_end);
    if absolute_start >= absolute_end
        || !is_zenuml_identifier(&source[absolute_start..absolute_end])
    {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedZenUmlMessage,
            span: Span::new(absolute_start, trimmed_end),
        });
    }
    Ok(Spanned::new(
        source[absolute_start..absolute_end].to_owned(),
        Span::new(absolute_start, absolute_end),
    ))
}

fn zenuml_target_end(source: &str, start: usize, end: usize) -> usize {
    source[start..end]
        .find(|value: char| value == '.' || value == '(' || value == ':' || value.is_whitespace())
        .map_or(end, |offset| start + offset)
}

fn zenuml_method_label(source: &str, start: usize, end: usize) -> Option<Label> {
    let dot = source[start..end].find('.')?;
    label_from_trimmed(source, start + dot + 1, end)
}

fn zenuml_decl_like(source: &str, has_annotator: bool) -> bool {
    has_annotator
        || source.split_ascii_whitespace().any(|part| part == "as")
        || is_zenuml_identifier(source.trim())
}

fn parse_zenuml_participant_decl(
    source: &str,
    start: usize,
    end: usize,
    annotator: Option<Spanned<String>>,
) -> Result<ZenUmlParticipant, ParseError> {
    let Some(as_start) = find_zenuml_as(source, start, end) else {
        let id = parse_zenuml_target(source, start, end).map_err(|_| ParseError {
            kind: ParseErrorKind::ExpectedZenUmlParticipant,
            span: Span::new(start, end),
        })?;
        return Ok(ZenUmlParticipant {
            id,
            label: None,
            annotator,
            span: Span::new(start, end),
        });
    };
    let id = parse_zenuml_target(source, start, as_start).map_err(|_| ParseError {
        kind: ParseErrorKind::ExpectedZenUmlParticipant,
        span: Span::new(start, as_start),
    })?;
    let label = label_from_trimmed(source, as_start + "as".len(), end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedZenUmlParticipant,
        span: Span::new(as_start + "as".len(), end),
    })?;
    Ok(ZenUmlParticipant {
        id,
        label: Some(label),
        annotator,
        span: Span::new(start, end),
    })
}

fn find_zenuml_as(source: &str, start: usize, end: usize) -> Option<usize> {
    let mut cursor = start;
    while cursor < end {
        let Some(offset) = source[cursor..end].find("as") else {
            return None;
        };
        let absolute = cursor + offset;
        let before = absolute == start
            || source
                .as_bytes()
                .get(absolute.saturating_sub(1))
                .is_some_and(u8::is_ascii_whitespace);
        let after = source
            .as_bytes()
            .get(absolute + "as".len())
            .is_some_and(u8::is_ascii_whitespace);
        if before && after {
            return Some(absolute);
        }
        cursor = absolute + "as".len();
    }
    None
}

fn is_zenuml_identifier(value: &str) -> bool {
    let mut bytes = value.bytes();
    let Some(first) = bytes.next() else {
        return false;
    };
    (first.is_ascii_alphabetic() || first == b'_' || first == b'$')
        && bytes.all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'$')
}

#[derive(Debug, Clone)]
struct ParsedTreemapNode {
    node: TreemapNode,
    children: Vec<usize>,
}

fn parse_treemap_node(source: &str) -> Result<TreemapNode, ParseError> {
    let Some((body_start, body_end)) = trim_ascii_range(source) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedTreemapNode,
            span: Span::new(0, 0),
        });
    };
    if source.as_bytes().get(body_start) != Some(&b'"') {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedTreemapNode,
            span: Span::new(body_start, body_end),
        });
    }
    let label_end = find_treemap_quote_end(source, body_start + 1, body_end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedTreemapNode,
        span: Span::new(body_start, body_end),
    })?;
    let label = label_from_body(source, body_start, label_end + 1);
    let mut cursor = skip_ascii_ws(source, label_end + 1, body_end);
    let mut value = None;
    let mut classes = Vec::new();
    while cursor < body_end {
        if source[cursor..body_end].starts_with(":::") {
            let class_end = treemap_class_token_end(source, cursor + 3, body_end);
            classes.extend(parse_treemap_classes(source, cursor + 3, class_end)?);
            cursor = skip_ascii_ws(source, class_end, body_end);
            continue;
        }
        if source.as_bytes().get(cursor) == Some(&b':') {
            let value_start = skip_ascii_ws(source, cursor + 1, body_end);
            let value_end = treemap_value_end(source, value_start, body_end);
            value = Some(parse_treemap_value(source, value_start, value_end)?);
            cursor = skip_ascii_ws(source, value_end, body_end);
            continue;
        }
        return Err(ParseError {
            kind: ParseErrorKind::UnknownTreemapStatement,
            span: Span::new(cursor, body_end),
        });
    }
    Ok(TreemapNode {
        label,
        value,
        classes,
        children: Vec::new(),
        span: Span::new(body_start, body_end),
    })
}

fn find_treemap_quote_end(source: &str, start: usize, end: usize) -> Option<usize> {
    let mut cursor = start;
    let mut escaped = false;
    while cursor < end {
        let byte = source.as_bytes()[cursor];
        if escaped {
            escaped = false;
        } else if byte == b'\\' {
            escaped = true;
        } else if byte == b'"' {
            return Some(cursor);
        }
        cursor += 1;
    }
    None
}

fn treemap_value_end(source: &str, start: usize, end: usize) -> usize {
    let class_start = source[start..end]
        .find(":::")
        .map_or(end, |offset| start + offset);
    trim_ascii_range(&source[start..class_start]).map_or(start, |(_, trim_end)| start + trim_end)
}

fn treemap_class_token_end(source: &str, start: usize, end: usize) -> usize {
    let mut cursor = start;
    while cursor < end && !source.as_bytes()[cursor].is_ascii_whitespace() {
        cursor += 1;
    }
    cursor
}

fn parse_treemap_value(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<String>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedTreemapValue,
            span: Span::new(start, end),
        });
    };
    let value_start = start + trim_start;
    let value_end = start + trim_end;
    let value = &source[value_start..value_end];
    let parsed = value.parse::<f64>().map_err(|_| ParseError {
        kind: ParseErrorKind::ExpectedTreemapValue,
        span: Span::new(value_start, value_end),
    })?;
    if !parsed.is_finite() || parsed < 0.0 {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedTreemapValue,
            span: Span::new(value_start, value_end),
        });
    }
    Ok(Spanned::new(
        value.to_owned(),
        Span::new(value_start, value_end),
    ))
}

fn parse_treemap_classes(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<Spanned<String>>, ParseError> {
    let mut classes = Vec::new();
    let mut token_start = start;
    let mut cursor = start;
    while cursor <= end {
        let split = cursor == end
            || source.as_bytes().get(cursor) == Some(&b',')
            || source[cursor..end].starts_with(":::");
        if split {
            push_treemap_class(source, token_start, cursor, &mut classes)?;
            if cursor < end && source[cursor..end].starts_with(":::") {
                cursor += 3;
            } else {
                cursor += 1;
            }
            token_start = cursor;
            continue;
        }
        cursor += 1;
    }
    if classes.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedTreemapNode,
            span: Span::new(start, end),
        });
    }
    Ok(classes)
}

fn push_treemap_class(
    source: &str,
    start: usize,
    end: usize,
    classes: &mut Vec<Spanned<String>>,
) -> Result<(), ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedTreemapNode,
            span: Span::new(start, end),
        });
    };
    let class_start = start + trim_start;
    let class_end = start + trim_end;
    if source[class_start..class_end]
        .chars()
        .any(|value| value.is_ascii_whitespace())
    {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedTreemapNode,
            span: Span::new(class_start, class_end),
        });
    }
    classes.push(Spanned::new(
        source[class_start..class_end].to_owned(),
        Span::new(class_start, class_end),
    ));
    Ok(())
}

fn build_treemap_node(index: usize, parsed: &[ParsedTreemapNode]) -> TreemapNode {
    let mut node = parsed[index].node.clone();
    node.children = parsed[index]
        .children
        .iter()
        .map(|child| build_treemap_node(*child, parsed))
        .collect();
    if let Some(last) = node.children.last() {
        node.span = Span::new(node.span.start, last.span.end);
    }
    node
}

#[derive(Debug, Clone)]
struct ParsedMindmapNode {
    node: MindmapNode,
    children: Vec<usize>,
}

fn parse_mindmap_icon(source: &str, offset: usize) -> Result<Option<Spanned<String>>, ParseError> {
    let Some(rest) = source.strip_prefix("::icon(") else {
        return Ok(None);
    };
    if !rest.ends_with(')') {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedMindmapNode,
            span: Span::new(offset, offset + source.len()),
        });
    }
    let start = "::icon(".len();
    let end = source.len() - 1;
    if start == end {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedMindmapNode,
            span: Span::new(offset + start, offset + end),
        });
    }
    Ok(Some(Spanned::new(
        source[start..end].to_owned(),
        Span::new(offset + start, offset + end),
    )))
}

fn parse_mindmap_class_apply(
    source: &str,
    offset: usize,
) -> Result<Option<Vec<Spanned<String>>>, ParseError> {
    if !source.starts_with(":::") {
        return Ok(None);
    }
    let classes = parse_mindmap_classes(source, 3, source.len(), offset);
    if classes.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedMindmapNode,
            span: Span::new(offset, offset + source.len()),
        });
    }
    Ok(Some(classes))
}

fn parse_mindmap_node(source: &str, offset: usize) -> Result<MindmapNode, ParseError> {
    let Some((body_start, body_end)) = trim_ascii_range(source) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedMindmapNode,
            span: Span::new(offset, offset),
        });
    };
    let mut node_end = body_end;
    let classes = if let Some(class_start) = source[body_start..body_end].find(":::") {
        let class_start = body_start + class_start;
        node_end = class_start;
        parse_mindmap_classes(source, class_start + 3, body_end, offset)
    } else {
        Vec::new()
    };
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[body_start..node_end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedMindmapNode,
            span: Span::new(offset + body_start, offset + node_end),
        });
    };
    let node_start = body_start + trim_start;
    let node_end = body_start + trim_end;
    let (shape, label_start, label_end) = mindmap_shape_label_bounds(source, node_start, node_end);
    if label_start == label_end {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedMindmapNode,
            span: Span::new(offset + node_start, offset + node_end),
        });
    }
    let label = shift_label(label_from_body(source, label_start, label_end), offset);
    Ok(MindmapNode {
        label,
        shape,
        icon: None,
        classes,
        children: Vec::new(),
        span: Span::new(offset + body_start, offset + body_end),
    })
}

fn parse_mindmap_classes(
    source: &str,
    start: usize,
    end: usize,
    offset: usize,
) -> Vec<Spanned<String>> {
    let mut classes = Vec::new();
    let mut cursor = start;
    while cursor < end {
        while cursor < end && source.as_bytes()[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        let token_start = cursor;
        while cursor < end && !source.as_bytes()[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        if token_start < cursor {
            classes.push(Spanned::new(
                source[token_start..cursor].to_owned(),
                Span::new(offset + token_start, offset + cursor),
            ));
        }
    }
    classes
}

fn mindmap_shape_label_bounds(
    source: &str,
    start: usize,
    end: usize,
) -> (MindmapShape, usize, usize) {
    for (open, close, shape) in [
        ("{{", "}}", MindmapShape::Hexagon),
        ("((", "))", MindmapShape::Circle),
        ("))", "((", MindmapShape::Bang),
        ("[", "]", MindmapShape::Square),
        ("(", ")", MindmapShape::Rounded),
        (")", "(", MindmapShape::Cloud),
    ] {
        if source[start..end].starts_with(open) && source[start..end].ends_with(close) {
            return (shape, start + open.len(), end - close.len());
        }
        if let Some(relative) = source[start..end].find(open)
            && source[start..end].ends_with(close)
        {
            let label_start = start + relative + open.len();
            return (shape, label_start, end - close.len());
        }
    }
    (MindmapShape::Default, start, end)
}

fn build_mindmap_node(index: usize, parsed: &[ParsedMindmapNode]) -> MindmapNode {
    let mut node = parsed[index].node.clone();
    node.children = parsed[index]
        .children
        .iter()
        .map(|child| build_mindmap_node(*child, parsed))
        .collect();
    node
}

fn parse_journey_tail(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(Spanned<u8>, Vec<Spanned<String>>), ParseError> {
    let score_end = source[start..end]
        .find(':')
        .map_or(end, |offset| start + offset);
    let score = parse_journey_score(source, start, score_end)?;
    let actors = if score_end == end {
        Vec::new()
    } else {
        parse_journey_actors(source, score_end + 1, end)
    };
    Ok((score, actors))
}

fn parse_journey_score(source: &str, start: usize, end: usize) -> Result<Spanned<u8>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedJourneyScore,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let Ok(score) = source[absolute_start..absolute_end].parse::<u8>() else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedJourneyScore,
            span: Span::new(absolute_start, absolute_end),
        });
    };
    if score == 0 || score > 5 {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedJourneyScore,
            span: Span::new(absolute_start, absolute_end),
        });
    }
    Ok(Spanned::new(score, Span::new(absolute_start, absolute_end)))
}

fn parse_journey_actors(source: &str, start: usize, end: usize) -> Vec<Spanned<String>> {
    let mut actors = Vec::new();
    let mut cursor = start;
    while cursor <= end {
        let actor_end = source[cursor..end]
            .find(',')
            .map_or(end, |offset| cursor + offset);
        if let Some((trim_start, trim_end)) = trim_ascii_range(&source[cursor..actor_end]) {
            let absolute_start = cursor + trim_start;
            let absolute_end = cursor + trim_end;
            actors.push(Spanned::new(
                source[absolute_start..absolute_end].to_owned(),
                Span::new(absolute_start, absolute_end),
            ));
        }
        if actor_end == end {
            break;
        }
        cursor = actor_end + 1;
    }
    actors
}

fn parse_timeline_period(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Option<TimelinePeriod>, ParseError> {
    let Some(colon) = source[start..end].find(':') else {
        return Ok(None);
    };
    let colon = start + colon;
    let label = label_from_trimmed(source, start, colon).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedTimelinePeriod,
        span: Span::new(start, colon),
    })?;
    let events = parse_timeline_events(source, colon + 1, end)?;
    Ok(Some(TimelinePeriod {
        label,
        section: None,
        events,
        span: Span::new(start, end),
    }))
}

fn parse_timeline_events(source: &str, start: usize, end: usize) -> Result<Vec<Label>, ParseError> {
    let mut events = Vec::new();
    let mut cursor = start;
    while cursor <= end {
        let event_end = source[cursor..end]
            .find(':')
            .map_or(end, |offset| cursor + offset);
        if let Some(event) = label_from_trimmed(source, cursor, event_end) {
            events.push(event);
        }
        if event_end == end {
            break;
        }
        cursor = event_end + 1;
    }
    if events.is_empty() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedTimelineEvent,
            span: Span::new(start, end),
        });
    }
    Ok(events)
}

fn parse_timeline_event(source: &str, start: usize, end: usize) -> Result<Label, ParseError> {
    label_from_trimmed(source, start, end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedTimelineEvent,
        span: Span::new(start, end),
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParsedRequirementName {
    name: Spanned<String>,
    classes: Vec<Spanned<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct RequirementToken {
    raw: String,
    span: Span,
}

fn is_requirement_node_block_header(source: &str) -> bool {
    let Some((start, end)) = trim_ascii_range(source) else {
        return false;
    };
    source[start..end].ends_with('{')
        && parse_requirement_kind_at(source, start, end.saturating_sub(1)).is_ok()
}

fn is_requirement_element_block_header(source: &str) -> bool {
    let Some((start, end)) = trim_ascii_range(source) else {
        return false;
    };
    source[start..end].ends_with('{') && has_keyword(source, start, "element")
}

fn parse_requirement_node_header(
    source: &str,
    start: usize,
    end: usize,
) -> Result<RequirementNode, ParseError> {
    let (kind, kind_span, name_start) = parse_requirement_kind_at(source, start, end)?;
    let parsed_name = parse_requirement_name_and_classes(source, name_start, end)?;
    Ok(RequirementNode {
        name: parsed_name.name,
        kind: Spanned::new(kind, kind_span),
        requirement_id: None,
        text: None,
        risk: None,
        verify_method: None,
        classes: parsed_name.classes,
        span: Span::new(start, end),
    })
}

fn parse_requirement_element_header(
    source: &str,
    start: usize,
    end: usize,
) -> Result<RequirementElement, ParseError> {
    if !has_keyword(source, start, "element") {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRequirementName,
            span: Span::new(start, end),
        });
    }
    let parsed_name = parse_requirement_name_and_classes(source, start + "element".len(), end)?;
    Ok(RequirementElement {
        name: parsed_name.name,
        ty: None,
        doc_ref: None,
        classes: parsed_name.classes,
        span: Span::new(start, end),
    })
}

fn parse_requirement_kind_at(
    source: &str,
    start: usize,
    end: usize,
) -> Result<(RequirementKind, Span, usize), ParseError> {
    for (keyword, kind) in [
        ("functionalRequirement", RequirementKind::Functional),
        ("interfaceRequirement", RequirementKind::Interface),
        ("performanceRequirement", RequirementKind::Performance),
        ("physicalRequirement", RequirementKind::Physical),
        ("designConstraint", RequirementKind::DesignConstraint),
        ("requirement", RequirementKind::Requirement),
    ] {
        if has_keyword(source, start, keyword) {
            return Ok((
                kind,
                Span::new(start, start + keyword.len()),
                start + keyword.len(),
            ));
        }
    }
    Err(ParseError {
        kind: ParseErrorKind::ExpectedRequirementKind,
        span: Span::new(start, end),
    })
}

fn parse_requirement_name_and_classes(
    source: &str,
    start: usize,
    end: usize,
) -> Result<ParsedRequirementName, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRequirementName,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let class_start = source[absolute_start..absolute_end]
        .rfind(":::")
        .map(|offset| absolute_start + offset);
    let name_end = class_start.unwrap_or(absolute_end);
    let Some((name_trim_start, name_trim_end)) =
        trim_ascii_range(&source[absolute_start..name_end])
    else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRequirementName,
            span: Span::new(absolute_start, name_end),
        });
    };
    let name_start = absolute_start + name_trim_start;
    let name_end = absolute_start + name_trim_end;
    let name = parse_requirement_name_token(source, name_start, name_end)?;
    let classes = class_start.map_or_else(Vec::new, |class_start| {
        parse_requirement_classes(source, class_start + 3, absolute_end)
    });
    Ok(ParsedRequirementName { name, classes })
}

fn parse_requirement_name_token(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<String>, ParseError> {
    if start == end {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRequirementName,
            span: Span::new(start, end),
        });
    }
    let label = label_from_body(source, start, end);
    Ok(Spanned::new(label.text, label.span))
}

fn parse_requirement_classes(source: &str, start: usize, end: usize) -> Vec<Spanned<String>> {
    let mut classes = Vec::new();
    let mut cursor = start;
    while cursor < end {
        while cursor < end && matches!(source.as_bytes().get(cursor), Some(b',' | b' ' | b'\t')) {
            cursor += 1;
        }
        let class_start = cursor;
        while cursor < end && !matches!(source.as_bytes().get(cursor), Some(b',' | b' ' | b'\t')) {
            cursor += 1;
        }
        if class_start < cursor {
            classes.push(Spanned::new(
                source[class_start..cursor].to_owned(),
                Span::new(class_start, cursor),
            ));
        }
    }
    classes
}

fn apply_requirement_field(
    node: &mut RequirementNode,
    source: &str,
    offset: usize,
) -> Result<(), ParseError> {
    let (key, value) = parse_requirement_field_pair(source, offset)?;
    let key_lower = key.value.to_ascii_lowercase();
    match key_lower.as_str() {
        "id" => node.requirement_id = Some(value),
        "text" => node.text = Some(value),
        "risk" => node.risk = Some(Spanned::new(parse_requirement_risk(&value)?, value.span)),
        "verifymethod" => {
            node.verify_method = Some(Spanned::new(
                parse_requirement_verify_method(&value)?,
                value.span,
            ));
        }
        _ => {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedRequirementField,
                span: key.span,
            });
        }
    }
    Ok(())
}

fn apply_requirement_element_field(
    element: &mut RequirementElement,
    source: &str,
    offset: usize,
) -> Result<(), ParseError> {
    let (key, value) = parse_requirement_field_pair(source, offset)?;
    match key.value.to_ascii_lowercase().as_str() {
        "type" => element.ty = Some(value),
        "docref" => element.doc_ref = Some(value),
        _ => {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedRequirementField,
                span: key.span,
            });
        }
    }
    Ok(())
}

fn parse_requirement_field_pair(
    source: &str,
    offset: usize,
) -> Result<(Spanned<String>, Label), ParseError> {
    let Some((start, end)) = trimmed_statement_bounds(source) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRequirementField,
            span: Span::new(offset, offset),
        });
    };
    let Some(colon) = source[start..end].find(':') else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedRequirementField,
            span: Span::new(offset + start, offset + end),
        });
    };
    let colon = start + colon;
    let key = parse_single_identifier(
        source,
        start,
        colon,
        ParseErrorKind::ExpectedRequirementField,
    )?;
    let value = label_from_trimmed(source, colon + 1, end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedRequirementField,
        span: Span::new(offset + colon + 1, offset + end),
    })?;
    Ok((shift_spanned(key, offset), shift_label(value, offset)))
}

fn parse_requirement_risk(label: &Label) -> Result<RequirementRisk, ParseError> {
    match label.text.to_ascii_lowercase().as_str() {
        "low" => Ok(RequirementRisk::Low),
        "medium" => Ok(RequirementRisk::Medium),
        "high" => Ok(RequirementRisk::High),
        _ => Err(ParseError {
            kind: ParseErrorKind::ExpectedRequirementRisk,
            span: label.span,
        }),
    }
}

fn parse_requirement_verify_method(label: &Label) -> Result<RequirementVerifyMethod, ParseError> {
    match label.text.to_ascii_lowercase().as_str() {
        "analysis" => Ok(RequirementVerifyMethod::Analysis),
        "inspection" => Ok(RequirementVerifyMethod::Inspection),
        "test" => Ok(RequirementVerifyMethod::Test),
        "demonstration" => Ok(RequirementVerifyMethod::Demonstration),
        _ => Err(ParseError {
            kind: ParseErrorKind::ExpectedRequirementVerifyMethod,
            span: label.span,
        }),
    }
}

fn parse_requirement_direction(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<Direction>, ParseError> {
    let value = parse_single_identifier(
        source,
        start + "direction".len(),
        end,
        ParseErrorKind::ExpectedRequirementField,
    )?;
    let direction = Direction::from_mermaid(&value.value).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedRequirementField,
        span: value.span,
    })?;
    Ok(Spanned::new(direction, value.span))
}

fn parse_requirement_style(
    source: &str,
    start: usize,
    end: usize,
) -> Result<RequirementStyle, ParseError> {
    let body_start = start + "style".len();
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[body_start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedStyleDeclaration,
            span: Span::new(body_start, end),
        });
    };
    let ids_start = body_start + trim_start;
    let body_end = body_start + trim_end;
    let ids_end = source[ids_start..body_end]
        .find(char::is_whitespace)
        .map_or(body_end, |offset| ids_start + offset);
    let node_ids = parse_csv_identifiers(
        source,
        ids_start,
        ids_end,
        ParseErrorKind::ExpectedRequirementName,
    )?;
    let styles = parse_style_declarations(source, ids_end, body_end)?;
    Ok(RequirementStyle {
        node_ids,
        styles,
        span: Span::new(start, end),
    })
}

fn parse_requirement_class_shorthand(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Option<FlowClassApply>, ParseError> {
    let Some(separator) = source[start..end].find(":::") else {
        return Ok(None);
    };
    let separator = start + separator;
    let node_ids = vec![parse_single_identifier(
        source,
        start,
        separator,
        ParseErrorKind::ExpectedRequirementName,
    )?];
    let class_ids = parse_flexible_identifiers(
        source,
        separator + 3,
        end,
        ParseErrorKind::ExpectedClassName,
    )?;
    Ok(Some(FlowClassApply {
        node_ids,
        class_ids,
        span: Span::new(start, end),
    }))
}

fn parse_requirement_relationship(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Option<RequirementRelationship>, ParseError> {
    let tokens = tokenize_requirement_statement(source, start, end)?;
    let Some([a, op_a, kind, op_b, b]) = tokens.as_slice().first_chunk::<5>() else {
        return Ok(None);
    };
    if tokens.len() != 5 {
        return Ok(None);
    }
    if op_a.raw == "-" && op_b.raw == "->" {
        return Ok(Some(RequirementRelationship {
            from: parse_requirement_name_token(source, a.span.start, a.span.end)?,
            to: parse_requirement_name_token(source, b.span.start, b.span.end)?,
            kind: parse_requirement_relationship_kind(kind)?,
            span: Span::new(start, end),
        }));
    }
    if op_a.raw == "<-" && op_b.raw == "-" {
        return Ok(Some(RequirementRelationship {
            from: parse_requirement_name_token(source, b.span.start, b.span.end)?,
            to: parse_requirement_name_token(source, a.span.start, a.span.end)?,
            kind: parse_requirement_relationship_kind(kind)?,
            span: Span::new(start, end),
        }));
    }
    Ok(None)
}

fn tokenize_requirement_statement(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<RequirementToken>, ParseError> {
    let mut tokens = Vec::new();
    let mut cursor = start;
    while cursor < end {
        while cursor < end && source.as_bytes()[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        if cursor >= end {
            break;
        }
        let token_start = cursor;
        if source.as_bytes()[cursor] == b'"' {
            cursor += 1;
            while cursor < end && source.as_bytes()[cursor] != b'"' {
                cursor += 1;
            }
            if cursor >= end {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedRequirementName,
                    span: Span::new(token_start, end),
                });
            }
            cursor += 1;
        } else {
            while cursor < end && !source.as_bytes()[cursor].is_ascii_whitespace() {
                cursor += 1;
            }
        }
        tokens.push(RequirementToken {
            raw: source[token_start..cursor].to_owned(),
            span: Span::new(token_start, cursor),
        });
    }
    Ok(tokens)
}

fn parse_requirement_relationship_kind(
    token: &RequirementToken,
) -> Result<Spanned<RequirementRelationshipKind>, ParseError> {
    let kind = match token.raw.to_ascii_lowercase().as_str() {
        "contains" => RequirementRelationshipKind::Contains,
        "copies" => RequirementRelationshipKind::Copies,
        "derives" => RequirementRelationshipKind::Derives,
        "satisfies" => RequirementRelationshipKind::Satisfies,
        "verifies" => RequirementRelationshipKind::Verifies,
        "refines" => RequirementRelationshipKind::Refines,
        "traces" => RequirementRelationshipKind::Traces,
        _ => {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedRequirementRelationship,
                span: token.span,
            });
        }
    };
    Ok(Spanned::new(kind, token.span))
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParsedC4Call {
    name: Spanned<String>,
    args: Vec<C4CallArg>,
    span: Span,
}

fn parse_c4_call(source: &str, start: usize, end: usize) -> Result<ParsedC4Call, ParseError> {
    let Some(open) = source[start..end].find('(').map(|offset| start + offset) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedC4Call,
            span: Span::new(start, end),
        });
    };
    let Some(close) = source[open + 1..end]
        .rfind(')')
        .map(|offset| open + 1 + offset)
    else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedC4Call,
            span: Span::new(open, end),
        });
    };
    let name = parse_single_identifier(source, start, open, ParseErrorKind::ExpectedC4Call)?;
    if trim_ascii_range(&source[close + 1..end]).is_some() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedC4Call,
            span: Span::new(close + 1, end),
        });
    }
    Ok(ParsedC4Call {
        name,
        args: parse_c4_args(source, open + 1, close)?,
        span: Span::new(start, end),
    })
}

fn parse_c4_args(source: &str, start: usize, end: usize) -> Result<Vec<C4CallArg>, ParseError> {
    let mut args = Vec::new();
    let mut cursor = start;
    while cursor < end {
        while cursor < end && matches!(source.as_bytes().get(cursor), Some(b',' | b' ' | b'\t')) {
            cursor += 1;
        }
        if cursor >= end {
            break;
        }
        let arg_start = cursor;
        let mut quoted = false;
        while cursor < end {
            let byte = source.as_bytes()[cursor];
            if byte == b'"' {
                quoted = !quoted;
                cursor += 1;
                continue;
            }
            if !quoted && byte == b',' {
                break;
            }
            cursor += 1;
        }
        let arg_end = cursor;
        if let Some(arg) = parse_c4_arg(source, arg_start, arg_end)? {
            args.push(arg);
        }
        if cursor < end && source.as_bytes()[cursor] == b',' {
            cursor += 1;
        }
    }
    Ok(args)
}

fn parse_c4_arg(source: &str, start: usize, end: usize) -> Result<Option<C4CallArg>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Ok(None);
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let (name, value_start, value_end) =
        if let Some(colon) = source[absolute_start..absolute_end].find(':') {
            let colon = absolute_start + colon;
            (
                Some(parse_c4_arg_name(source, absolute_start, colon)?),
                colon + 1,
                absolute_end,
            )
        } else if source.as_bytes().get(absolute_start) == Some(&b'$') {
            let mut cursor = absolute_start + 1;
            while cursor < absolute_end
                && (source.as_bytes()[cursor].is_ascii_alphanumeric()
                    || source.as_bytes()[cursor] == b'_')
            {
                cursor += 1;
            }
            if cursor < absolute_end && source.as_bytes()[cursor] == b'=' {
                (
                    Some(Spanned::new(
                        source[absolute_start + 1..cursor].to_owned(),
                        Span::new(absolute_start + 1, cursor),
                    )),
                    cursor + 1,
                    absolute_end,
                )
            } else {
                (None, absolute_start, absolute_end)
            }
        } else {
            (None, absolute_start, absolute_end)
        };
    let value = label_from_trimmed(source, value_start, value_end).ok_or(ParseError {
        kind: ParseErrorKind::ExpectedC4Argument,
        span: Span::new(value_start, value_end),
    })?;
    Ok(Some(C4CallArg {
        name,
        value,
        span: Span::new(absolute_start, absolute_end),
    }))
}

fn parse_c4_arg_name(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<String>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedC4Argument,
            span: Span::new(start, end),
        });
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let name = source[absolute_start..absolute_end]
        .strip_prefix('$')
        .unwrap_or(&source[absolute_start..absolute_end]);
    if !is_identifier(name) {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedC4Argument,
            span: Span::new(absolute_start, absolute_end),
        });
    }
    Ok(Spanned::new(
        name.to_owned(),
        Span::new(absolute_end - name.len(), absolute_end),
    ))
}

fn c4_element_from_call(call: &ParsedC4Call) -> Result<Option<C4Element>, ParseError> {
    let Some((kind, external)) = c4_element_kind(&call.name.value) else {
        return Ok(None);
    };
    let alias = c4_arg_identifier(call, 0, &["alias", "id"])?;
    let label = c4_arg_label(call, 1, &["label", "name"])?;
    let has_technology = !matches!(
        kind,
        C4ElementKind::Person
            | C4ElementKind::PersonExternal
            | C4ElementKind::System
            | C4ElementKind::SystemExternal
            | C4ElementKind::SystemDb
            | C4ElementKind::SystemDbExternal
            | C4ElementKind::SystemQueue
            | C4ElementKind::SystemQueueExternal
    );
    let technology = if has_technology {
        c4_arg_optional_label(call, 2, &["techn", "technology"])?
    } else {
        None
    };
    let description = if has_technology {
        c4_arg_optional_label(call, 3, &["descr", "description"])?
    } else {
        c4_arg_optional_label(call, 2, &["descr", "description"])?
    };
    Ok(Some(C4Element {
        alias,
        label,
        kind: Spanned::new(kind, call.name.span),
        technology,
        description,
        parent: None,
        external,
        span: call.span,
    }))
}

fn c4_boundary_from_call(call: &ParsedC4Call) -> Result<Option<C4Boundary>, ParseError> {
    let Some(kind) = c4_boundary_kind(&call.name.value) else {
        return Ok(None);
    };
    let alias = c4_arg_identifier(call, 0, &["alias", "id"])?;
    let label = c4_arg_label(call, 1, &["label", "name"])?;
    let ty = c4_arg_optional_label(call, 2, &["type", "techn", "technology"])?;
    Ok(Some(C4Boundary {
        alias,
        label,
        kind: Spanned::new(kind, call.name.span),
        ty,
        parent: None,
        span: call.span,
    }))
}

fn c4_relationship_from_call(call: &ParsedC4Call) -> Result<Option<C4Relationship>, ParseError> {
    let Some((kind, indexed, bidirectional)) = c4_relationship_kind(&call.name.value) else {
        return Ok(None);
    };
    let offset = usize::from(indexed);
    let index = if indexed {
        Some(c4_arg_raw(call, 0, &["index", "idx"])?)
    } else {
        None
    };
    let from = c4_arg_identifier(call, offset, &["from", "fromAlias"])?;
    let to = c4_arg_identifier(call, offset + 1, &["to", "toAlias"])?;
    let label = c4_arg_label(call, offset + 2, &["label"])?;
    let technology = c4_arg_optional_label(call, offset + 3, &["techn", "technology"])?;
    let kind = if bidirectional {
        C4RelationshipKind::Bidirectional
    } else {
        kind
    };
    Ok(Some(C4Relationship {
        from,
        to,
        label,
        technology,
        kind: Spanned::new(kind, call.name.span),
        index,
        span: call.span,
    }))
}

fn c4_style_from_call(call: &ParsedC4Call) -> Result<Option<C4StyleUpdate>, ParseError> {
    if !matches!(
        call.name.value.as_str(),
        "UpdateElementStyle" | "UpdateRelStyle" | "UpdateBoundaryStyle"
    ) {
        return Ok(None);
    }
    let target = c4_arg_identifier(call, 0, &["alias", "id", "target"])?;
    Ok(Some(C4StyleUpdate {
        target_ids: vec![target],
        fields: call.args.iter().skip(1).cloned().collect(),
        span: call.span,
    }))
}

fn c4_element_kind(name: &str) -> Option<(C4ElementKind, bool)> {
    let value = match name {
        "Person" => (C4ElementKind::Person, false),
        "Person_Ext" | "Person_External" => (C4ElementKind::PersonExternal, true),
        "System" => (C4ElementKind::System, false),
        "System_Ext" | "System_External" => (C4ElementKind::SystemExternal, true),
        "SystemDb" => (C4ElementKind::SystemDb, false),
        "SystemDb_Ext" => (C4ElementKind::SystemDbExternal, true),
        "SystemQueue" => (C4ElementKind::SystemQueue, false),
        "SystemQueue_Ext" => (C4ElementKind::SystemQueueExternal, true),
        "Container" => (C4ElementKind::Container, false),
        "Container_Ext" => (C4ElementKind::ContainerExternal, true),
        "ContainerDb" => (C4ElementKind::ContainerDb, false),
        "ContainerDb_Ext" => (C4ElementKind::ContainerDbExternal, true),
        "ContainerQueue" => (C4ElementKind::ContainerQueue, false),
        "ContainerQueue_Ext" => (C4ElementKind::ContainerQueueExternal, true),
        "Component" => (C4ElementKind::Component, false),
        "Component_Ext" => (C4ElementKind::ComponentExternal, true),
        "ComponentDb" => (C4ElementKind::ComponentDb, false),
        "ComponentDb_Ext" => (C4ElementKind::ComponentDbExternal, true),
        "ComponentQueue" => (C4ElementKind::ComponentQueue, false),
        "ComponentQueue_Ext" => (C4ElementKind::ComponentQueueExternal, true),
        _ => return None,
    };
    Some(value)
}

fn c4_boundary_kind(name: &str) -> Option<C4BoundaryKind> {
    match name {
        "Boundary" => Some(C4BoundaryKind::Boundary),
        "Enterprise_Boundary" => Some(C4BoundaryKind::Enterprise),
        "System_Boundary" => Some(C4BoundaryKind::System),
        "Container_Boundary" => Some(C4BoundaryKind::Container),
        "Deployment_Node" | "Deployment_Node_L" | "Deployment_Node_R" | "Node" | "Node_L"
        | "Node_R" => Some(C4BoundaryKind::DeploymentNode),
        _ => None,
    }
}

fn c4_relationship_kind(name: &str) -> Option<(C4RelationshipKind, bool, bool)> {
    match name {
        "Rel" => Some((C4RelationshipKind::Directed, false, false)),
        "BiRel" => Some((C4RelationshipKind::Directed, false, true)),
        "Rel_U" | "Rel_Up" => Some((C4RelationshipKind::Up, false, false)),
        "Rel_D" | "Rel_Down" => Some((C4RelationshipKind::Down, false, false)),
        "Rel_L" | "Rel_Left" => Some((C4RelationshipKind::Left, false, false)),
        "Rel_R" | "Rel_Right" => Some((C4RelationshipKind::Right, false, false)),
        "Rel_Back" => Some((C4RelationshipKind::Back, false, false)),
        "RelIndex" => Some((C4RelationshipKind::Indexed, true, false)),
        "BiRelIndex" => Some((C4RelationshipKind::Indexed, true, true)),
        _ => None,
    }
}

fn is_c4_layout_call(name: &str) -> bool {
    matches!(
        name,
        "LAYOUT_TOP_DOWN"
            | "LAYOUT_LEFT_RIGHT"
            | "LAYOUT_WITH_LEGEND"
            | "SHOW_LEGEND"
            | "HIDE_STEREOTYPE"
            | "SHOW_FLOATING_LEGEND"
            | "Lay_U"
            | "Lay_D"
            | "Lay_L"
            | "Lay_R"
            | "Lay_Up"
            | "Lay_Down"
            | "Lay_Left"
            | "Lay_Right"
            | "Lay_Back"
            | "UpdateLayoutConfig"
    )
}

fn c4_arg_identifier(
    call: &ParsedC4Call,
    position: usize,
    names: &[&str],
) -> Result<Spanned<String>, ParseError> {
    let arg = c4_arg(call, position, names)?;
    Ok(Spanned::new(arg.value.text.clone(), arg.value.span))
}

fn c4_arg_raw(
    call: &ParsedC4Call,
    position: usize,
    names: &[&str],
) -> Result<Spanned<String>, ParseError> {
    let arg = c4_arg(call, position, names)?;
    Ok(Spanned::new(arg.value.text.clone(), arg.value.span))
}

fn c4_arg_label(call: &ParsedC4Call, position: usize, names: &[&str]) -> Result<Label, ParseError> {
    Ok(c4_arg(call, position, names)?.value.clone())
}

fn c4_arg_optional_label(
    call: &ParsedC4Call,
    position: usize,
    names: &[&str],
) -> Result<Option<Label>, ParseError> {
    Ok(c4_optional_arg(call, position, names)?.map(|arg| arg.value.clone()))
}

fn c4_arg<'a>(
    call: &'a ParsedC4Call,
    position: usize,
    names: &[&str],
) -> Result<&'a C4CallArg, ParseError> {
    c4_optional_arg(call, position, names)?.ok_or(ParseError {
        kind: ParseErrorKind::ExpectedC4Argument,
        span: call.span,
    })
}

fn c4_optional_arg<'a>(
    call: &'a ParsedC4Call,
    position: usize,
    names: &[&str],
) -> Result<Option<&'a C4CallArg>, ParseError> {
    if let Some(arg) = call.args.iter().find(|arg| {
        arg.name
            .as_ref()
            .is_some_and(|name| names.iter().any(|candidate| name.value == *candidate))
    }) {
        return Ok(Some(arg));
    }
    Ok(call
        .args
        .iter()
        .filter(|arg| arg.name.is_none())
        .nth(position))
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParsedGitGraphName {
    value: Spanned<String>,
    consumed_end: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParsedGitGraphAttribute {
    key: Spanned<String>,
    value: Spanned<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParsedGitGraphCommitAttributes {
    id: Option<Spanned<String>>,
    tag: Option<Spanned<String>>,
    kind: Spanned<GitGraphCommitKind>,
}

fn parse_gitgraph_orientation(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Spanned<GitGraphOrientation>, ParseError> {
    let Some((trim_start, trim_end)) = trim_ascii_range(&source[start..end]) else {
        return Ok(Spanned::new(
            GitGraphOrientation::LeftRight,
            Span::new(start, start),
        ));
    };
    let absolute_start = start + trim_start;
    let absolute_end = start + trim_end;
    let token = source[absolute_start..absolute_end]
        .strip_suffix(':')
        .unwrap_or(&source[absolute_start..absolute_end]);
    if token.is_empty() {
        return Ok(Spanned::new(
            GitGraphOrientation::LeftRight,
            Span::new(absolute_start, absolute_end),
        ));
    }
    let orientation = match token {
        "LR" => GitGraphOrientation::LeftRight,
        "TB" => GitGraphOrientation::TopBottom,
        "BT" => GitGraphOrientation::BottomTop,
        _ => {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedGitGraphHeader,
                span: Span::new(absolute_start, absolute_end),
            });
        }
    };
    Ok(Spanned::new(
        orientation,
        Span::new(absolute_start, absolute_end),
    ))
}

fn is_gitgraph_header_keyword(source: &str, start: usize, end: usize) -> bool {
    let rest_start = start + "gitGraph".len();
    source[start..end].starts_with("gitGraph")
        && (rest_start == end
            || source.as_bytes()[rest_start].is_ascii_whitespace()
            || source.as_bytes()[rest_start] == b':')
}

fn parse_gitgraph_commit(
    source: &str,
    start: usize,
    end: usize,
) -> Result<GitGraphCommit, ParseError> {
    let attrs = parse_gitgraph_attributes(source, start + "commit".len(), end)?;
    let parsed = gitgraph_commit_attributes(attrs, start)?;
    Ok(GitGraphCommit {
        id: parsed.id,
        tag: parsed.tag,
        kind: parsed.kind,
        span: Span::new(start, end),
    })
}

fn parse_gitgraph_branch(
    source: &str,
    start: usize,
    end: usize,
) -> Result<GitGraphBranch, ParseError> {
    let name = parse_gitgraph_name_at(source, start + "branch".len(), end)?;
    let attrs = parse_gitgraph_attributes(source, name.consumed_end, end)?;
    let mut order = None;
    for attr in attrs {
        match attr.key.value.as_str() {
            "order" => {
                let parsed = attr.value.value.parse::<i32>().map_err(|_| ParseError {
                    kind: ParseErrorKind::ExpectedGitGraphAttribute,
                    span: attr.value.span,
                })?;
                order = Some(Spanned::new(parsed, attr.value.span));
            }
            _ => {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedGitGraphAttribute,
                    span: attr.key.span,
                });
            }
        }
    }
    Ok(GitGraphBranch {
        name: name.value,
        order,
        span: Span::new(start, end),
    })
}

fn parse_gitgraph_keyword_name(
    source: &str,
    start: usize,
    end: usize,
    keyword: &str,
) -> Result<Spanned<String>, ParseError> {
    let name = parse_gitgraph_name_at(source, start + keyword.len(), end)?;
    if trim_ascii_range(&source[name.consumed_end..end]).is_some() {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedGitGraphName,
            span: Span::new(name.consumed_end, end),
        });
    }
    Ok(name.value)
}

fn parse_gitgraph_merge(
    source: &str,
    start: usize,
    end: usize,
) -> Result<GitGraphMerge, ParseError> {
    let branch = parse_gitgraph_name_at(source, start + "merge".len(), end)?;
    let attrs = parse_gitgraph_attributes(source, branch.consumed_end, end)?;
    let parsed = gitgraph_commit_attributes(attrs, start)?;
    Ok(GitGraphMerge {
        branch: branch.value,
        id: parsed.id,
        tag: parsed.tag,
        kind: parsed.kind,
        span: Span::new(start, end),
    })
}

fn parse_gitgraph_cherry_pick(
    source: &str,
    start: usize,
    end: usize,
) -> Result<GitGraphCherryPick, ParseError> {
    let attrs = parse_gitgraph_attributes(source, start + "cherry-pick".len(), end)?;
    let mut id = None;
    let mut parent = None;
    for attr in attrs {
        match attr.key.value.as_str() {
            "id" => id = Some(attr.value),
            "parent" => parent = Some(attr.value),
            _ => {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedGitGraphAttribute,
                    span: attr.key.span,
                });
            }
        }
    }
    let id = id.ok_or(ParseError {
        kind: ParseErrorKind::ExpectedGitGraphAttribute,
        span: Span::new(start, end),
    })?;
    Ok(GitGraphCherryPick {
        id,
        parent,
        span: Span::new(start, end),
    })
}

fn gitgraph_commit_attributes(
    attrs: Vec<ParsedGitGraphAttribute>,
    default_span_start: usize,
) -> Result<ParsedGitGraphCommitAttributes, ParseError> {
    let mut id = None;
    let mut tag = None;
    let mut kind = Spanned::new(
        GitGraphCommitKind::Normal,
        Span::new(default_span_start, default_span_start),
    );
    for attr in attrs {
        match attr.key.value.as_str() {
            "id" => id = Some(attr.value),
            "tag" => tag = Some(attr.value),
            "type" => {
                let parsed = parse_gitgraph_commit_kind(&attr.value)?;
                kind = Spanned::new(parsed, attr.value.span);
            }
            _ => {
                return Err(ParseError {
                    kind: ParseErrorKind::ExpectedGitGraphAttribute,
                    span: attr.key.span,
                });
            }
        }
    }
    Ok(ParsedGitGraphCommitAttributes { id, tag, kind })
}

fn parse_gitgraph_commit_kind(value: &Spanned<String>) -> Result<GitGraphCommitKind, ParseError> {
    match value.value.as_str() {
        "NORMAL" => Ok(GitGraphCommitKind::Normal),
        "REVERSE" => Ok(GitGraphCommitKind::Reverse),
        "HIGHLIGHT" => Ok(GitGraphCommitKind::Highlight),
        _ => Err(ParseError {
            kind: ParseErrorKind::ExpectedGitGraphCommitKind,
            span: value.span,
        }),
    }
}

fn parse_gitgraph_attributes(
    source: &str,
    start: usize,
    end: usize,
) -> Result<Vec<ParsedGitGraphAttribute>, ParseError> {
    let mut attrs = Vec::new();
    let mut cursor = start;
    while let Some(next) = skip_ascii_whitespace(source, cursor, end) {
        cursor = next;
        let key_start = cursor;
        while cursor < end
            && !source.as_bytes()[cursor].is_ascii_whitespace()
            && source.as_bytes()[cursor] != b':'
        {
            cursor += 1;
        }
        let key_end = cursor;
        if key_start == key_end {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedGitGraphAttribute,
                span: Span::new(cursor, end),
            });
        }
        cursor = skip_ascii_whitespace(source, cursor, end).unwrap_or(cursor);
        if cursor >= end || source.as_bytes()[cursor] != b':' {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedGitGraphAttribute,
                span: Span::new(key_start, key_end),
            });
        }
        cursor += 1;
        let value = parse_gitgraph_name_at(source, cursor, end)?;
        attrs.push(ParsedGitGraphAttribute {
            key: Spanned::new(
                source[key_start..key_end].to_owned(),
                Span::new(key_start, key_end),
            ),
            value: value.value,
        });
        cursor = value.consumed_end;
    }
    Ok(attrs)
}

fn parse_gitgraph_name_at(
    source: &str,
    start: usize,
    end: usize,
) -> Result<ParsedGitGraphName, ParseError> {
    let Some(cursor) = skip_ascii_whitespace(source, start, end) else {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedGitGraphName,
            span: Span::new(start, end),
        });
    };
    if source.as_bytes()[cursor] == b'"' {
        let value_start = cursor + 1;
        let Some(relative_end) = source[value_start..end].find('"') else {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedGitGraphName,
                span: Span::new(cursor, end),
            });
        };
        let value_end = value_start + relative_end;
        if value_start == value_end {
            return Err(ParseError {
                kind: ParseErrorKind::ExpectedGitGraphName,
                span: Span::new(value_start, value_end),
            });
        }
        return Ok(ParsedGitGraphName {
            value: Spanned::new(
                source[value_start..value_end].to_owned(),
                Span::new(value_start, value_end),
            ),
            consumed_end: value_end + 1,
        });
    }
    let mut cursor_end = cursor;
    while cursor_end < end && !source.as_bytes()[cursor_end].is_ascii_whitespace() {
        cursor_end += 1;
    }
    if cursor == cursor_end {
        return Err(ParseError {
            kind: ParseErrorKind::ExpectedGitGraphName,
            span: Span::new(start, end),
        });
    }
    Ok(ParsedGitGraphName {
        value: Spanned::new(
            source[cursor..cursor_end].to_owned(),
            Span::new(cursor, cursor_end),
        ),
        consumed_end: cursor_end,
    })
}

fn skip_ascii_whitespace(source: &str, start: usize, end: usize) -> Option<usize> {
    let mut cursor = start;
    while cursor < end && source.as_bytes()[cursor].is_ascii_whitespace() {
        cursor += 1;
    }
    (cursor < end).then_some(cursor)
}

fn shift_span(span: Span, offset: usize) -> Span {
    Span::new(span.start + offset, span.end + offset)
}

fn shift_error(error: ParseError, offset: usize) -> ParseError {
    ParseError {
        kind: error.kind,
        span: shift_span(error.span, offset),
    }
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
        SequenceStatement::Create(create) => {
            SequenceStatement::Create(Box::new(shift_sequence_create(*create, offset)))
        }
        SequenceStatement::Destroy(destroy) => {
            SequenceStatement::Destroy(Box::new(shift_sequence_destroy(*destroy, offset)))
        }
        SequenceStatement::Box(sequence_box) => {
            SequenceStatement::Box(Box::new(shift_sequence_box(*sequence_box, offset)))
        }
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

fn shift_sequence_create(create: SequenceCreate, offset: usize) -> SequenceCreate {
    SequenceCreate {
        participant: shift_sequence_participant(create.participant, offset),
        span: shift_span(create.span, offset),
    }
}

fn shift_sequence_destroy(destroy: SequenceDestroy, offset: usize) -> SequenceDestroy {
    SequenceDestroy {
        participant: shift_spanned(destroy.participant, offset),
        span: shift_span(destroy.span, offset),
    }
}

fn shift_sequence_box(sequence_box: SequenceBox, offset: usize) -> SequenceBox {
    SequenceBox {
        label: sequence_box.label.map(|label| shift_label(label, offset)),
        participants: sequence_box
            .participants
            .into_iter()
            .map(|participant| shift_spanned(participant, offset))
            .collect(),
        span: shift_span(sequence_box.span, offset),
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
        activation: message
            .activation
            .map(|activation| shift_spanned(activation, offset)),
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
        start: auto_number.start.map(|start| shift_spanned(start, offset)),
        step: auto_number.step.map(|step| shift_spanned(step, offset)),
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
        start_cardinality: relationship
            .start_cardinality
            .map(|cardinality| shift_label(cardinality, offset)),
        end_cardinality: relationship
            .end_cardinality
            .map(|cardinality| shift_label(cardinality, offset)),
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

fn shift_gantt_header(header: GanttHeader, offset: usize) -> GanttHeader {
    GanttHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_gantt_statement(statement: GanttStatement, offset: usize) -> GanttStatement {
    match statement {
        GanttStatement::Title(title) => GanttStatement::Title(shift_label(title, offset)),
        GanttStatement::DateFormat(format) => {
            GanttStatement::DateFormat(shift_spanned(format, offset))
        }
        GanttStatement::AxisFormat(format) => {
            GanttStatement::AxisFormat(shift_spanned(format, offset))
        }
        GanttStatement::Section(section) => GanttStatement::Section(shift_label(section, offset)),
        GanttStatement::Task(task) => {
            GanttStatement::Task(Box::new(shift_gantt_task(*task, offset)))
        }
        GanttStatement::Config(config) => {
            GanttStatement::Config(shift_gantt_config(config, offset))
        }
        GanttStatement::Comment(comment) => GanttStatement::Comment(shift_comment(comment, offset)),
        GanttStatement::Directive(directive) => {
            GanttStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_gantt_config(config: GanttConfigStatement, offset: usize) -> GanttConfigStatement {
    GanttConfigStatement {
        key: shift_spanned(config.key, offset),
        value: config.value.map(|value| shift_label(value, offset)),
        span: shift_span(config.span, offset),
    }
}

fn shift_gantt_task(task: GanttTask, offset: usize) -> GanttTask {
    GanttTask {
        title: shift_label(task.title, offset),
        section: task.section.map(|section| shift_label(section, offset)),
        tags: task.tags,
        id: task.id.map(|id| shift_spanned(id, offset)),
        metadata: task
            .metadata
            .into_iter()
            .map(|value| shift_spanned(value, offset))
            .collect(),
        span: shift_span(task.span, offset),
    }
}

fn shift_pie_header(header: PieHeader, offset: usize) -> PieHeader {
    PieHeader {
        show_data: header.show_data,
        title: header.title.map(|title| shift_label(title, offset)),
        span: shift_span(header.span, offset),
    }
}

fn shift_pie_statement(statement: PieStatement, offset: usize) -> PieStatement {
    match statement {
        PieStatement::Title(title) => PieStatement::Title(shift_label(title, offset)),
        PieStatement::Slice(slice) => PieStatement::Slice(shift_pie_slice(slice, offset)),
        PieStatement::Comment(comment) => PieStatement::Comment(shift_comment(comment, offset)),
        PieStatement::Directive(directive) => {
            PieStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_pie_slice(slice: PieSlice, offset: usize) -> PieSlice {
    PieSlice {
        label: shift_label(slice.label, offset),
        value_units: shift_spanned(slice.value_units, offset),
        value_text: shift_spanned(slice.value_text, offset),
        span: shift_span(slice.span, offset),
    }
}

fn shift_quadrant_header(header: QuadrantHeader, offset: usize) -> QuadrantHeader {
    QuadrantHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_quadrant_statement(statement: QuadrantStatement, offset: usize) -> QuadrantStatement {
    match statement {
        QuadrantStatement::Title(title) => QuadrantStatement::Title(shift_label(title, offset)),
        QuadrantStatement::Axis(axis) => QuadrantStatement::Axis(shift_quadrant_axis(axis, offset)),
        QuadrantStatement::Quadrant(section) => {
            QuadrantStatement::Quadrant(shift_quadrant_section(section, offset))
        }
        QuadrantStatement::Point(point) => {
            QuadrantStatement::Point(Box::new(shift_quadrant_point(*point, offset)))
        }
        QuadrantStatement::ClassDef(class_def) => {
            QuadrantStatement::ClassDef(shift_class_def(class_def, offset))
        }
        QuadrantStatement::ClassApply(class_apply) => {
            QuadrantStatement::ClassApply(shift_class_apply(class_apply, offset))
        }
        QuadrantStatement::Comment(comment) => {
            QuadrantStatement::Comment(shift_comment(comment, offset))
        }
        QuadrantStatement::Directive(directive) => {
            QuadrantStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_quadrant_axis(axis: QuadrantAxis, offset: usize) -> QuadrantAxis {
    QuadrantAxis {
        kind: shift_spanned(axis.kind, offset),
        start: shift_label(axis.start, offset),
        end: shift_label(axis.end, offset),
        span: shift_span(axis.span, offset),
    }
}

fn shift_quadrant_section(section: QuadrantSection, offset: usize) -> QuadrantSection {
    QuadrantSection {
        index: shift_spanned(section.index, offset),
        label: shift_label(section.label, offset),
        span: shift_span(section.span, offset),
    }
}

fn shift_quadrant_point(point: QuadrantPoint, offset: usize) -> QuadrantPoint {
    QuadrantPoint {
        label: shift_label(point.label, offset),
        x: shift_spanned(point.x, offset),
        y: shift_spanned(point.y, offset),
        span: shift_span(point.span, offset),
    }
}

fn shift_zenuml_header(header: ZenUmlHeader, offset: usize) -> ZenUmlHeader {
    ZenUmlHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_zenuml_statement(statement: ZenUmlStatement, offset: usize) -> ZenUmlStatement {
    match statement {
        ZenUmlStatement::Title(title) => ZenUmlStatement::Title(shift_label(title, offset)),
        ZenUmlStatement::Participant(participant) => {
            ZenUmlStatement::Participant(shift_zenuml_participant(participant, offset))
        }
        ZenUmlStatement::Message(message) => {
            ZenUmlStatement::Message(Box::new(shift_zenuml_message(*message, offset)))
        }
        ZenUmlStatement::Fragment(fragment) => {
            ZenUmlStatement::Fragment(shift_zenuml_fragment(fragment, offset))
        }
        ZenUmlStatement::BlockEnd(span) => ZenUmlStatement::BlockEnd(shift_span(span, offset)),
        ZenUmlStatement::Comment(comment) => {
            ZenUmlStatement::Comment(shift_comment(comment, offset))
        }
        ZenUmlStatement::Directive(directive) => {
            ZenUmlStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_zenuml_participant(participant: ZenUmlParticipant, offset: usize) -> ZenUmlParticipant {
    ZenUmlParticipant {
        id: shift_spanned(participant.id, offset),
        label: participant.label.map(|label| shift_label(label, offset)),
        annotator: participant
            .annotator
            .map(|annotator| shift_spanned(annotator, offset)),
        span: shift_span(participant.span, offset),
    }
}

fn shift_zenuml_message(message: ZenUmlMessage, offset: usize) -> ZenUmlMessage {
    ZenUmlMessage {
        from: message.from.map(|from| shift_spanned(from, offset)),
        to: shift_spanned(message.to, offset),
        label: message.label.map(|label| shift_label(label, offset)),
        kind: shift_spanned(message.kind, offset),
        depth: message.depth,
        span: shift_span(message.span, offset),
    }
}

fn shift_zenuml_fragment(fragment: ZenUmlFragment, offset: usize) -> ZenUmlFragment {
    ZenUmlFragment {
        kind: shift_spanned(fragment.kind, offset),
        label: fragment.label.map(|label| shift_label(label, offset)),
        depth: fragment.depth,
        span: shift_span(fragment.span, offset),
    }
}

fn shift_sankey_header(header: SankeyHeader, offset: usize) -> SankeyHeader {
    SankeyHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_sankey_statement(statement: SankeyStatement, offset: usize) -> SankeyStatement {
    match statement {
        SankeyStatement::Link(link) => {
            SankeyStatement::Link(Box::new(shift_sankey_link(*link, offset)))
        }
        SankeyStatement::Comment(comment) => {
            SankeyStatement::Comment(shift_comment(comment, offset))
        }
        SankeyStatement::Directive(directive) => {
            SankeyStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_sankey_link(link: SankeyLink, offset: usize) -> SankeyLink {
    SankeyLink {
        source: shift_label(link.source, offset),
        target: shift_label(link.target, offset),
        value_units: shift_spanned(link.value_units, offset),
        value_text: shift_spanned(link.value_text, offset),
        span: shift_span(link.span, offset),
    }
}

fn shift_xy_chart_header(header: XyChartHeader, offset: usize) -> XyChartHeader {
    XyChartHeader {
        orientation: header
            .orientation
            .map(|orientation| shift_spanned(orientation, offset)),
        span: shift_span(header.span, offset),
    }
}

fn shift_xy_chart_statement(statement: XyChartStatement, offset: usize) -> XyChartStatement {
    match statement {
        XyChartStatement::Title(title) => XyChartStatement::Title(shift_label(title, offset)),
        XyChartStatement::Axis(axis) => XyChartStatement::Axis(shift_xy_chart_axis(axis, offset)),
        XyChartStatement::Series(series) => {
            XyChartStatement::Series(shift_xy_chart_series(series, offset))
        }
        XyChartStatement::Comment(comment) => {
            XyChartStatement::Comment(shift_comment(comment, offset))
        }
        XyChartStatement::Directive(directive) => {
            XyChartStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_xy_chart_axis(axis: XyChartAxis, offset: usize) -> XyChartAxis {
    XyChartAxis {
        kind: shift_spanned(axis.kind, offset),
        title: axis.title.map(|title| shift_label(title, offset)),
        scale: axis
            .scale
            .map(|scale| shift_xy_chart_axis_scale(scale, offset)),
        span: shift_span(axis.span, offset),
    }
}

fn shift_xy_chart_axis_scale(scale: XyChartAxisScale, offset: usize) -> XyChartAxisScale {
    match scale {
        XyChartAxisScale::Categories(labels) => XyChartAxisScale::Categories(
            labels
                .into_iter()
                .map(|label| shift_label(label, offset))
                .collect(),
        ),
        XyChartAxisScale::Range { min, max } => XyChartAxisScale::Range {
            min: shift_spanned(min, offset),
            max: shift_spanned(max, offset),
        },
    }
}

fn shift_xy_chart_series(series: XyChartSeries, offset: usize) -> XyChartSeries {
    XyChartSeries {
        kind: shift_spanned(series.kind, offset),
        values: series
            .values
            .into_iter()
            .map(|value| shift_spanned(value, offset))
            .collect(),
        value_texts: series
            .value_texts
            .into_iter()
            .map(|value| shift_spanned(value, offset))
            .collect(),
        span: shift_span(series.span, offset),
    }
}

fn shift_block_header(header: BlockDiagramHeader, offset: usize) -> BlockDiagramHeader {
    BlockDiagramHeader {
        columns: header.columns.map(|columns| shift_spanned(columns, offset)),
        span: shift_span(header.span, offset),
    }
}

fn shift_block_statement(statement: BlockStatement, offset: usize) -> BlockStatement {
    match statement {
        BlockStatement::Columns(columns) => BlockStatement::Columns(shift_spanned(columns, offset)),
        BlockStatement::Node(node) => {
            BlockStatement::Node(Box::new(shift_block_node(*node, offset)))
        }
        BlockStatement::Space(space) => BlockStatement::Space(BlockSpace {
            width: shift_spanned(space.width, offset),
            span: shift_span(space.span, offset),
        }),
        BlockStatement::Container(container) => {
            BlockStatement::Container(Box::new(shift_block_container(*container, offset)))
        }
        BlockStatement::Edge(edge) => {
            BlockStatement::Edge(Box::new(shift_block_edge(*edge, offset)))
        }
        BlockStatement::ClassDef(class_def) => {
            BlockStatement::ClassDef(shift_class_def(class_def, offset))
        }
        BlockStatement::ClassApply(class_apply) => {
            BlockStatement::ClassApply(shift_class_apply(class_apply, offset))
        }
        BlockStatement::Style(style) => BlockStatement::Style(shift_block_style(style, offset)),
        BlockStatement::Comment(comment) => BlockStatement::Comment(shift_comment(comment, offset)),
        BlockStatement::Directive(directive) => {
            BlockStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_block_container_header_only(container: BlockContainer, offset: usize) -> BlockContainer {
    BlockContainer {
        id: container.id.map(|id| shift_spanned(id, offset)),
        width: shift_spanned(container.width, offset),
        columns: container
            .columns
            .map(|columns| shift_spanned(columns, offset)),
        statements: container.statements,
        span: container.span,
    }
}

fn shift_block_container(container: BlockContainer, offset: usize) -> BlockContainer {
    BlockContainer {
        id: container.id.map(|id| shift_spanned(id, offset)),
        width: shift_spanned(container.width, offset),
        columns: container
            .columns
            .map(|columns| shift_spanned(columns, offset)),
        statements: container
            .statements
            .into_iter()
            .map(|statement| shift_block_statement(statement, offset))
            .collect(),
        span: shift_span(container.span, offset),
    }
}

fn shift_block_node(node: BlockNode, offset: usize) -> BlockNode {
    BlockNode {
        id: shift_spanned(node.id, offset),
        label: node.label.map(|label| shift_label(label, offset)),
        shape: shift_block_shape(node.shape, offset),
        width: shift_spanned(node.width, offset),
        span: shift_span(node.span, offset),
    }
}

fn shift_block_shape(shape: Spanned<BlockShape>, offset: usize) -> Spanned<BlockShape> {
    let value = match shape.value {
        BlockShape::Flow(shape) => BlockShape::Flow(shape),
        BlockShape::Arrow(directions) => BlockShape::Arrow(
            directions
                .into_iter()
                .map(|direction| shift_spanned(direction, offset))
                .collect(),
        ),
    };
    Spanned::new(value, shift_span(shape.span, offset))
}

fn shift_block_edge(edge: BlockEdge, offset: usize) -> BlockEdge {
    BlockEdge {
        from: shift_spanned(edge.from, offset),
        to: shift_spanned(edge.to, offset),
        from_node: shift_block_node(edge.from_node, offset),
        to_node: shift_block_node(edge.to_node, offset),
        link: shift_spanned(edge.link, offset),
        label: edge.label.map(|label| shift_label(label, offset)),
        span: shift_span(edge.span, offset),
    }
}

fn shift_block_style(style: BlockStyle, offset: usize) -> BlockStyle {
    BlockStyle {
        target: shift_spanned(style.target, offset),
        styles: style
            .styles
            .into_iter()
            .map(|style| shift_style_declaration(style, offset))
            .collect(),
        span: shift_span(style.span, offset),
    }
}

fn shift_packet_header(header: PacketHeader, offset: usize) -> PacketHeader {
    PacketHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_packet_statement(statement: PacketStatement, offset: usize) -> PacketStatement {
    match statement {
        PacketStatement::Title(title) => PacketStatement::Title(shift_label(title, offset)),
        PacketStatement::Field(field) => {
            PacketStatement::Field(Box::new(shift_packet_field(*field, offset)))
        }
        PacketStatement::Comment(comment) => {
            PacketStatement::Comment(shift_comment(comment, offset))
        }
        PacketStatement::Directive(directive) => {
            PacketStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_packet_field(field: PacketField, offset: usize) -> PacketField {
    PacketField {
        range: PacketRange {
            start: shift_spanned(field.range.start, offset),
            end: shift_spanned(field.range.end, offset),
            span: shift_span(field.range.span, offset),
        },
        label: shift_label(field.label, offset),
        span: shift_span(field.span, offset),
    }
}

fn shift_kanban_header(header: KanbanHeader, offset: usize) -> KanbanHeader {
    KanbanHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_kanban_item(item: KanbanParsedItem, offset: usize) -> KanbanParsedItem {
    KanbanParsedItem {
        id: item.id.map(|id| shift_spanned(id, offset)),
        label: shift_label(item.label, offset),
        metadata: item
            .metadata
            .into_iter()
            .map(|metadata| shift_kanban_metadata(metadata, offset))
            .collect(),
        span: shift_span(item.span, offset),
    }
}

fn shift_kanban_metadata(metadata: KanbanMetadata, offset: usize) -> KanbanMetadata {
    KanbanMetadata {
        key: shift_spanned(metadata.key, offset),
        value: shift_label(metadata.value, offset),
        span: shift_span(metadata.span, offset),
    }
}

fn shift_architecture_header(header: ArchitectureHeader, offset: usize) -> ArchitectureHeader {
    ArchitectureHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_architecture_statement(
    statement: ArchitectureStatement,
    offset: usize,
) -> ArchitectureStatement {
    match statement {
        ArchitectureStatement::Group(group) => {
            ArchitectureStatement::Group(Box::new(shift_architecture_group(*group, offset)))
        }
        ArchitectureStatement::Service(service) => {
            ArchitectureStatement::Service(Box::new(shift_architecture_service(*service, offset)))
        }
        ArchitectureStatement::Junction(junction) => ArchitectureStatement::Junction(Box::new(
            shift_architecture_junction(*junction, offset),
        )),
        ArchitectureStatement::Edge(edge) => {
            ArchitectureStatement::Edge(Box::new(shift_architecture_edge(*edge, offset)))
        }
        ArchitectureStatement::Alignment(alignment) => ArchitectureStatement::Alignment(Box::new(
            shift_architecture_alignment(*alignment, offset),
        )),
        ArchitectureStatement::Comment(comment) => {
            ArchitectureStatement::Comment(shift_comment(comment, offset))
        }
        ArchitectureStatement::Directive(directive) => {
            ArchitectureStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_architecture_group(group: ArchitectureGroup, offset: usize) -> ArchitectureGroup {
    ArchitectureGroup {
        id: shift_spanned(group.id, offset),
        icon: group.icon.map(|icon| shift_label(icon, offset)),
        title: group.title.map(|title| shift_label(title, offset)),
        parent: group.parent.map(|parent| shift_spanned(parent, offset)),
        span: shift_span(group.span, offset),
    }
}

fn shift_architecture_service(service: ArchitectureService, offset: usize) -> ArchitectureService {
    ArchitectureService {
        id: shift_spanned(service.id, offset),
        icon: service.icon.map(|icon| shift_label(icon, offset)),
        title: service.title.map(|title| shift_label(title, offset)),
        parent: service.parent.map(|parent| shift_spanned(parent, offset)),
        span: shift_span(service.span, offset),
    }
}

fn shift_architecture_junction(
    junction: ArchitectureJunction,
    offset: usize,
) -> ArchitectureJunction {
    ArchitectureJunction {
        id: shift_spanned(junction.id, offset),
        parent: junction.parent.map(|parent| shift_spanned(parent, offset)),
        span: shift_span(junction.span, offset),
    }
}

fn shift_architecture_edge(edge: ArchitectureEdge, offset: usize) -> ArchitectureEdge {
    ArchitectureEdge {
        from: shift_architecture_endpoint(edge.from, offset),
        to: shift_architecture_endpoint(edge.to, offset),
        arrow_start: edge.arrow_start,
        arrow_end: edge.arrow_end,
        span: shift_span(edge.span, offset),
    }
}

fn shift_architecture_endpoint(
    endpoint: ArchitectureEndpoint,
    offset: usize,
) -> ArchitectureEndpoint {
    ArchitectureEndpoint {
        id: shift_spanned(endpoint.id, offset),
        side: shift_spanned(endpoint.side, offset),
        group: endpoint.group,
        span: shift_span(endpoint.span, offset),
    }
}

fn shift_architecture_alignment(
    alignment: ArchitectureAlignment,
    offset: usize,
) -> ArchitectureAlignment {
    ArchitectureAlignment {
        axis: shift_spanned(alignment.axis, offset),
        members: alignment
            .members
            .into_iter()
            .map(|member| shift_spanned(member, offset))
            .collect(),
        span: shift_span(alignment.span, offset),
    }
}

fn shift_radar_header(header: RadarHeader, offset: usize) -> RadarHeader {
    RadarHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_radar_statement(statement: RadarStatement, offset: usize) -> RadarStatement {
    match statement {
        RadarStatement::Title(title) => RadarStatement::Title(shift_label(title, offset)),
        RadarStatement::Axis(axis) => {
            RadarStatement::Axis(Box::new(shift_radar_axis(*axis, offset)))
        }
        RadarStatement::Curve(curve) => {
            RadarStatement::Curve(Box::new(shift_radar_curve(*curve, offset)))
        }
        RadarStatement::Option(option) => {
            RadarStatement::Option(Box::new(shift_radar_option(*option, offset)))
        }
        RadarStatement::Comment(comment) => RadarStatement::Comment(shift_comment(comment, offset)),
        RadarStatement::Directive(directive) => {
            RadarStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_radar_axis(axis: RadarAxis, offset: usize) -> RadarAxis {
    RadarAxis {
        id: shift_spanned(axis.id, offset),
        label: axis.label.map(|label| shift_label(label, offset)),
        span: shift_span(axis.span, offset),
    }
}

fn shift_radar_curve(curve: RadarCurve, offset: usize) -> RadarCurve {
    RadarCurve {
        id: shift_spanned(curve.id, offset),
        label: curve.label.map(|label| shift_label(label, offset)),
        values: curve
            .values
            .into_iter()
            .map(|value| shift_radar_curve_value(value, offset))
            .collect(),
        span: shift_span(curve.span, offset),
    }
}

fn shift_radar_curve_value(value: RadarCurveValue, offset: usize) -> RadarCurveValue {
    RadarCurveValue {
        axis: value.axis.map(|axis| shift_spanned(axis, offset)),
        value: shift_spanned(value.value, offset),
        span: shift_span(value.span, offset),
    }
}

fn shift_radar_option(option: RadarOption, offset: usize) -> RadarOption {
    RadarOption {
        kind: shift_spanned(option.kind, offset),
        value: shift_spanned(option.value, offset),
        span: shift_span(option.span, offset),
    }
}

fn shift_event_modeling_header(header: EventModelingHeader, offset: usize) -> EventModelingHeader {
    EventModelingHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_event_modeling_statement(
    statement: EventModelingStatement,
    offset: usize,
) -> EventModelingStatement {
    match statement {
        EventModelingStatement::TimeFrame(frame) => EventModelingStatement::TimeFrame(Box::new(
            shift_event_modeling_timeframe(*frame, offset),
        )),
        EventModelingStatement::DataBlock(block) => EventModelingStatement::DataBlock(Box::new(
            shift_event_modeling_data_block(*block, offset),
        )),
        EventModelingStatement::Comment(comment) => {
            EventModelingStatement::Comment(shift_comment(comment, offset))
        }
        EventModelingStatement::Directive(directive) => {
            EventModelingStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_event_modeling_timeframe(
    frame: EventModelingTimeFrame,
    offset: usize,
) -> EventModelingTimeFrame {
    EventModelingTimeFrame {
        kind: shift_spanned(frame.kind, offset),
        number: shift_spanned(frame.number, offset),
        entity_type: shift_spanned(frame.entity_type, offset),
        entity: shift_spanned(frame.entity, offset),
        data_ref: frame
            .data_ref
            .map(|data_ref| shift_spanned(data_ref, offset)),
        data: frame
            .data
            .map(|data| shift_event_modeling_data(data, offset)),
        relations: frame
            .relations
            .into_iter()
            .map(|relation| shift_spanned(relation, offset))
            .collect(),
        span: shift_span(frame.span, offset),
    }
}

fn shift_event_modeling_data_block(
    block: EventModelingDataBlock,
    offset: usize,
) -> EventModelingDataBlock {
    EventModelingDataBlock {
        id: shift_spanned(block.id, offset),
        data: shift_event_modeling_data(block.data, offset),
        span: shift_span(block.span, offset),
    }
}

fn shift_event_modeling_data(data: EventModelingData, offset: usize) -> EventModelingData {
    EventModelingData {
        ty: data.ty.map(|ty| shift_spanned(ty, offset)),
        body: shift_label(data.body, offset),
        span: shift_span(data.span, offset),
    }
}

fn shift_treemap_header(header: TreemapHeader, offset: usize) -> TreemapHeader {
    TreemapHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_treemap_node(node: TreemapNode, offset: usize) -> TreemapNode {
    TreemapNode {
        label: shift_label(node.label, offset),
        value: node.value.map(|value| shift_spanned(value, offset)),
        classes: node
            .classes
            .into_iter()
            .map(|class| shift_spanned(class, offset))
            .collect(),
        children: node
            .children
            .into_iter()
            .map(|child| shift_treemap_node(child, offset))
            .collect(),
        span: shift_span(node.span, offset),
    }
}

fn shift_venn_header(header: VennHeader, offset: usize) -> VennHeader {
    VennHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_venn_statement(statement: VennStatement, offset: usize) -> VennStatement {
    match statement {
        VennStatement::Title(title) => VennStatement::Title(shift_label(title, offset)),
        VennStatement::Set(set) => VennStatement::Set(Box::new(shift_venn_set(*set, offset))),
        VennStatement::Union(union) => {
            VennStatement::Union(Box::new(shift_venn_union(*union, offset)))
        }
        VennStatement::Text(text) => VennStatement::Text(Box::new(shift_venn_text(*text, offset))),
        VennStatement::Style(style) => VennStatement::Style(shift_venn_style(style, offset)),
        VennStatement::Comment(comment) => VennStatement::Comment(shift_comment(comment, offset)),
        VennStatement::Directive(directive) => {
            VennStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_venn_set(set: VennSet, offset: usize) -> VennSet {
    VennSet {
        id: shift_spanned(set.id, offset),
        label: set.label.map(|label| shift_label(label, offset)),
        size: set.size.map(|size| shift_spanned(size, offset)),
        texts: set
            .texts
            .into_iter()
            .map(|text| shift_venn_text(text, offset))
            .collect(),
        span: shift_span(set.span, offset),
    }
}

fn shift_venn_union(union: VennUnion, offset: usize) -> VennUnion {
    VennUnion {
        members: union
            .members
            .into_iter()
            .map(|member| shift_spanned(member, offset))
            .collect(),
        label: union.label.map(|label| shift_label(label, offset)),
        size: union.size.map(|size| shift_spanned(size, offset)),
        texts: union
            .texts
            .into_iter()
            .map(|text| shift_venn_text(text, offset))
            .collect(),
        span: shift_span(union.span, offset),
    }
}

fn shift_venn_text(text: VennText, offset: usize) -> VennText {
    VennText {
        id: shift_spanned(text.id, offset),
        label: text.label.map(|label| shift_label(label, offset)),
        owner: text.owner,
        span: shift_span(text.span, offset),
    }
}

fn shift_venn_style(style: VennStyle, offset: usize) -> VennStyle {
    VennStyle {
        targets: style
            .targets
            .into_iter()
            .map(|target| shift_spanned(target, offset))
            .collect(),
        declarations: style
            .declarations
            .into_iter()
            .map(|declaration| shift_style_declaration(declaration, offset))
            .collect(),
        span: shift_span(style.span, offset),
    }
}

fn shift_ishikawa_header(header: IshikawaHeader, offset: usize) -> IshikawaHeader {
    IshikawaHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_wardley_header(header: WardleyHeader, offset: usize) -> WardleyHeader {
    WardleyHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_wardley_statement(statement: WardleyStatement, offset: usize) -> WardleyStatement {
    match statement {
        WardleyStatement::Title(title) => WardleyStatement::Title(shift_label(title, offset)),
        WardleyStatement::Size(size) => WardleyStatement::Size(shift_wardley_size(size, offset)),
        WardleyStatement::Component(component) => {
            WardleyStatement::Component(Box::new(shift_wardley_component(*component, offset)))
        }
        WardleyStatement::Link(link) => WardleyStatement::Link(shift_wardley_link(link, offset)),
        WardleyStatement::Evolve(evolve) => {
            WardleyStatement::Evolve(shift_wardley_evolve(evolve, offset))
        }
        WardleyStatement::Note(note) => WardleyStatement::Note(shift_wardley_note(note, offset)),
        WardleyStatement::Annotations(coord) => {
            WardleyStatement::Annotations(shift_wardley_coord(coord, offset))
        }
        WardleyStatement::Annotation(annotation) => {
            WardleyStatement::Annotation(shift_wardley_annotation(annotation, offset))
        }
        WardleyStatement::Force(force) => {
            WardleyStatement::Force(shift_wardley_force(force, offset))
        }
        WardleyStatement::Evolution(evolution) => {
            WardleyStatement::Evolution(shift_wardley_evolution(evolution, offset))
        }
        WardleyStatement::Pipeline(label) => WardleyStatement::Pipeline(shift_label(label, offset)),
        WardleyStatement::Comment(comment) => {
            WardleyStatement::Comment(shift_comment(comment, offset))
        }
        WardleyStatement::Directive(directive) => {
            WardleyStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_wardley_size(size: WardleySize, offset: usize) -> WardleySize {
    WardleySize {
        width: size.width,
        height: size.height,
        span: shift_span(size.span, offset),
    }
}

fn shift_wardley_component(component: WardleyComponent, offset: usize) -> WardleyComponent {
    WardleyComponent {
        kind: component.kind,
        name: shift_label(component.name, offset),
        coord: shift_wardley_coord(component.coord, offset),
        label_offset: component
            .label_offset
            .map(|label_offset| shift_wardley_label_offset(label_offset, offset)),
        decorators: component.decorators,
        pipeline: component
            .pipeline
            .map(|pipeline| shift_label(pipeline, offset)),
        span: shift_span(component.span, offset),
    }
}

fn shift_wardley_coord(coord: WardleyCoord, offset: usize) -> WardleyCoord {
    WardleyCoord {
        visibility: shift_spanned(coord.visibility, offset),
        evolution: shift_spanned(coord.evolution, offset),
        span: shift_span(coord.span, offset),
    }
}

fn shift_wardley_label_offset(
    label_offset: WardleyLabelOffset,
    offset: usize,
) -> WardleyLabelOffset {
    WardleyLabelOffset {
        x: label_offset.x,
        y: label_offset.y,
        span: shift_span(label_offset.span, offset),
    }
}

fn shift_wardley_link(link: WardleyLink, offset: usize) -> WardleyLink {
    WardleyLink {
        from: shift_label(link.from, offset),
        to: shift_label(link.to, offset),
        kind: link.kind,
        label: link.label.map(|label| shift_label(label, offset)),
        span: shift_span(link.span, offset),
    }
}

fn shift_wardley_evolve(evolve: WardleyEvolve, offset: usize) -> WardleyEvolve {
    WardleyEvolve {
        name: shift_label(evolve.name, offset),
        target_evolution: shift_spanned(evolve.target_evolution, offset),
        span: shift_span(evolve.span, offset),
    }
}

fn shift_wardley_note(note: WardleyNote, offset: usize) -> WardleyNote {
    WardleyNote {
        text: shift_label(note.text, offset),
        coord: shift_wardley_coord(note.coord, offset),
        span: shift_span(note.span, offset),
    }
}

fn shift_wardley_annotation(annotation: WardleyAnnotation, offset: usize) -> WardleyAnnotation {
    WardleyAnnotation {
        number: shift_spanned(annotation.number, offset),
        coord: shift_wardley_coord(annotation.coord, offset),
        text: shift_label(annotation.text, offset),
        span: shift_span(annotation.span, offset),
    }
}

fn shift_wardley_force(force: WardleyForce, offset: usize) -> WardleyForce {
    WardleyForce {
        kind: force.kind,
        text: shift_label(force.text, offset),
        coord: shift_wardley_coord(force.coord, offset),
        span: shift_span(force.span, offset),
    }
}

fn shift_wardley_evolution(evolution: WardleyEvolution, offset: usize) -> WardleyEvolution {
    WardleyEvolution {
        stages: evolution
            .stages
            .into_iter()
            .map(|stage| WardleyEvolutionStage {
                label: shift_label(stage.label, offset),
                boundary: stage
                    .boundary
                    .map(|boundary| shift_spanned(boundary, offset)),
                span: shift_span(stage.span, offset),
            })
            .collect(),
        span: shift_span(evolution.span, offset),
    }
}

fn shift_mindmap_header(header: MindmapHeader, offset: usize) -> MindmapHeader {
    MindmapHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_journey_header(header: JourneyHeader, offset: usize) -> JourneyHeader {
    JourneyHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_journey_statement(statement: JourneyStatement, offset: usize) -> JourneyStatement {
    match statement {
        JourneyStatement::Title(title) => JourneyStatement::Title(shift_label(title, offset)),
        JourneyStatement::Section(section) => {
            JourneyStatement::Section(shift_label(section, offset))
        }
        JourneyStatement::Task(task) => {
            JourneyStatement::Task(Box::new(shift_journey_task(*task, offset)))
        }
        JourneyStatement::Comment(comment) => {
            JourneyStatement::Comment(shift_comment(comment, offset))
        }
        JourneyStatement::Directive(directive) => {
            JourneyStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_journey_task(task: JourneyTask, offset: usize) -> JourneyTask {
    JourneyTask {
        label: shift_label(task.label, offset),
        section: task.section.map(|section| shift_label(section, offset)),
        score: shift_spanned(task.score, offset),
        actors: task
            .actors
            .into_iter()
            .map(|actor| shift_spanned(actor, offset))
            .collect(),
        span: shift_span(task.span, offset),
    }
}

fn shift_gitgraph_header(header: GitGraphHeader, offset: usize) -> GitGraphHeader {
    GitGraphHeader {
        orientation: shift_spanned(header.orientation, offset),
        span: shift_span(header.span, offset),
    }
}

fn shift_gitgraph_statement(statement: GitGraphStatement, offset: usize) -> GitGraphStatement {
    match statement {
        GitGraphStatement::Commit(commit) => {
            GitGraphStatement::Commit(Box::new(shift_gitgraph_commit(*commit, offset)))
        }
        GitGraphStatement::Branch(branch) => {
            GitGraphStatement::Branch(Box::new(shift_gitgraph_branch(*branch, offset)))
        }
        GitGraphStatement::Checkout(branch) => {
            GitGraphStatement::Checkout(shift_spanned(branch, offset))
        }
        GitGraphStatement::Merge(merge) => {
            GitGraphStatement::Merge(Box::new(shift_gitgraph_merge(*merge, offset)))
        }
        GitGraphStatement::CherryPick(cherry_pick) => GitGraphStatement::CherryPick(Box::new(
            shift_gitgraph_cherry_pick(*cherry_pick, offset),
        )),
        GitGraphStatement::Comment(comment) => {
            GitGraphStatement::Comment(shift_comment(comment, offset))
        }
        GitGraphStatement::Directive(directive) => {
            GitGraphStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_gitgraph_commit(commit: GitGraphCommit, offset: usize) -> GitGraphCommit {
    GitGraphCommit {
        id: commit.id.map(|id| shift_spanned(id, offset)),
        tag: commit.tag.map(|tag| shift_spanned(tag, offset)),
        kind: shift_spanned(commit.kind, offset),
        span: shift_span(commit.span, offset),
    }
}

fn shift_gitgraph_branch(branch: GitGraphBranch, offset: usize) -> GitGraphBranch {
    GitGraphBranch {
        name: shift_spanned(branch.name, offset),
        order: branch.order.map(|order| shift_spanned(order, offset)),
        span: shift_span(branch.span, offset),
    }
}

fn shift_gitgraph_merge(merge: GitGraphMerge, offset: usize) -> GitGraphMerge {
    GitGraphMerge {
        branch: shift_spanned(merge.branch, offset),
        id: merge.id.map(|id| shift_spanned(id, offset)),
        tag: merge.tag.map(|tag| shift_spanned(tag, offset)),
        kind: shift_spanned(merge.kind, offset),
        span: shift_span(merge.span, offset),
    }
}

fn shift_gitgraph_cherry_pick(
    cherry_pick: GitGraphCherryPick,
    offset: usize,
) -> GitGraphCherryPick {
    GitGraphCherryPick {
        id: shift_spanned(cherry_pick.id, offset),
        parent: cherry_pick
            .parent
            .map(|parent| shift_spanned(parent, offset)),
        span: shift_span(cherry_pick.span, offset),
    }
}

fn shift_timeline_header(header: TimelineHeader, offset: usize) -> TimelineHeader {
    TimelineHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_timeline_statement(statement: TimelineStatement, offset: usize) -> TimelineStatement {
    match statement {
        TimelineStatement::Title(title) => TimelineStatement::Title(shift_label(title, offset)),
        TimelineStatement::Section(section) => {
            TimelineStatement::Section(shift_label(section, offset))
        }
        TimelineStatement::Period(period) => {
            TimelineStatement::Period(Box::new(shift_timeline_period(*period, offset)))
        }
        TimelineStatement::Event(event) => TimelineStatement::Event(shift_label(event, offset)),
        TimelineStatement::Comment(comment) => {
            TimelineStatement::Comment(shift_comment(comment, offset))
        }
        TimelineStatement::Directive(directive) => {
            TimelineStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_timeline_period(period: TimelinePeriod, offset: usize) -> TimelinePeriod {
    TimelinePeriod {
        label: shift_label(period.label, offset),
        section: period.section.map(|section| shift_label(section, offset)),
        events: period
            .events
            .into_iter()
            .map(|event| shift_label(event, offset))
            .collect(),
        span: shift_span(period.span, offset),
    }
}

fn shift_requirement_header(header: RequirementHeader, offset: usize) -> RequirementHeader {
    RequirementHeader {
        span: shift_span(header.span, offset),
    }
}

fn shift_requirement_statement(
    statement: RequirementStatement,
    offset: usize,
) -> RequirementStatement {
    match statement {
        RequirementStatement::Requirement(node) => {
            RequirementStatement::Requirement(Box::new(shift_requirement_node(*node, offset)))
        }
        RequirementStatement::Element(element) => {
            RequirementStatement::Element(Box::new(shift_requirement_element(*element, offset)))
        }
        RequirementStatement::Relationship(relationship) => RequirementStatement::Relationship(
            Box::new(shift_requirement_relationship(*relationship, offset)),
        ),
        RequirementStatement::Direction(direction) => {
            RequirementStatement::Direction(shift_spanned(direction, offset))
        }
        RequirementStatement::Style(style) => {
            RequirementStatement::Style(shift_requirement_style(style, offset))
        }
        RequirementStatement::ClassDef(class_def) => {
            RequirementStatement::ClassDef(shift_class_def(class_def, offset))
        }
        RequirementStatement::ClassApply(class_apply) => {
            RequirementStatement::ClassApply(shift_class_apply(class_apply, offset))
        }
        RequirementStatement::Comment(comment) => {
            RequirementStatement::Comment(shift_comment(comment, offset))
        }
        RequirementStatement::Directive(directive) => {
            RequirementStatement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_requirement_node(node: RequirementNode, offset: usize) -> RequirementNode {
    RequirementNode {
        name: shift_spanned(node.name, offset),
        kind: shift_spanned(node.kind, offset),
        requirement_id: node
            .requirement_id
            .map(|requirement_id| shift_label(requirement_id, offset)),
        text: node.text.map(|text| shift_label(text, offset)),
        risk: node.risk.map(|risk| shift_spanned(risk, offset)),
        verify_method: node
            .verify_method
            .map(|verify_method| shift_spanned(verify_method, offset)),
        classes: node
            .classes
            .into_iter()
            .map(|class| shift_spanned(class, offset))
            .collect(),
        span: shift_span(node.span, offset),
    }
}

fn shift_requirement_element(element: RequirementElement, offset: usize) -> RequirementElement {
    RequirementElement {
        name: shift_spanned(element.name, offset),
        ty: element.ty.map(|ty| shift_label(ty, offset)),
        doc_ref: element.doc_ref.map(|doc_ref| shift_label(doc_ref, offset)),
        classes: element
            .classes
            .into_iter()
            .map(|class| shift_spanned(class, offset))
            .collect(),
        span: shift_span(element.span, offset),
    }
}

fn shift_requirement_relationship(
    relationship: RequirementRelationship,
    offset: usize,
) -> RequirementRelationship {
    RequirementRelationship {
        from: shift_spanned(relationship.from, offset),
        to: shift_spanned(relationship.to, offset),
        kind: shift_spanned(relationship.kind, offset),
        span: shift_span(relationship.span, offset),
    }
}

fn shift_requirement_style(style: RequirementStyle, offset: usize) -> RequirementStyle {
    RequirementStyle {
        node_ids: style
            .node_ids
            .into_iter()
            .map(|node_id| shift_spanned(node_id, offset))
            .collect(),
        styles: style
            .styles
            .into_iter()
            .map(|style| shift_style_declaration(style, offset))
            .collect(),
        span: shift_span(style.span, offset),
    }
}

fn shift_c4_header(header: C4Header, offset: usize) -> C4Header {
    C4Header {
        diagram_type: shift_spanned(header.diagram_type, offset),
        span: shift_span(header.span, offset),
    }
}

fn shift_c4_statement(statement: C4Statement, offset: usize) -> C4Statement {
    match statement {
        C4Statement::Title(title) => C4Statement::Title(shift_label(title, offset)),
        C4Statement::Element(element) => {
            C4Statement::Element(Box::new(shift_c4_element(*element, offset)))
        }
        C4Statement::Relationship(relationship) => {
            C4Statement::Relationship(Box::new(shift_c4_relationship(*relationship, offset)))
        }
        C4Statement::Boundary(boundary) => {
            C4Statement::Boundary(Box::new(shift_c4_boundary(*boundary, offset)))
        }
        C4Statement::Style(style) => C4Statement::Style(shift_c4_style(style, offset)),
        C4Statement::Layout(layout) => C4Statement::Layout(shift_c4_layout(layout, offset)),
        C4Statement::Comment(comment) => C4Statement::Comment(shift_comment(comment, offset)),
        C4Statement::Directive(directive) => {
            C4Statement::Directive(shift_directive(directive, offset))
        }
    }
}

fn shift_c4_element(element: C4Element, offset: usize) -> C4Element {
    C4Element {
        alias: shift_spanned(element.alias, offset),
        label: shift_label(element.label, offset),
        kind: shift_spanned(element.kind, offset),
        technology: element
            .technology
            .map(|technology| shift_label(technology, offset)),
        description: element
            .description
            .map(|description| shift_label(description, offset)),
        parent: element.parent.map(|parent| shift_spanned(parent, offset)),
        external: element.external,
        span: shift_span(element.span, offset),
    }
}

fn shift_c4_boundary(boundary: C4Boundary, offset: usize) -> C4Boundary {
    C4Boundary {
        alias: shift_spanned(boundary.alias, offset),
        label: shift_label(boundary.label, offset),
        kind: shift_spanned(boundary.kind, offset),
        ty: boundary.ty.map(|ty| shift_label(ty, offset)),
        parent: boundary.parent.map(|parent| shift_spanned(parent, offset)),
        span: shift_span(boundary.span, offset),
    }
}

fn shift_c4_relationship(relationship: C4Relationship, offset: usize) -> C4Relationship {
    C4Relationship {
        from: shift_spanned(relationship.from, offset),
        to: shift_spanned(relationship.to, offset),
        label: shift_label(relationship.label, offset),
        technology: relationship
            .technology
            .map(|technology| shift_label(technology, offset)),
        kind: shift_spanned(relationship.kind, offset),
        index: relationship.index.map(|index| shift_spanned(index, offset)),
        span: shift_span(relationship.span, offset),
    }
}

fn shift_c4_style(style: C4StyleUpdate, offset: usize) -> C4StyleUpdate {
    C4StyleUpdate {
        target_ids: style
            .target_ids
            .into_iter()
            .map(|target| shift_spanned(target, offset))
            .collect(),
        fields: style
            .fields
            .into_iter()
            .map(|field| shift_c4_arg(field, offset))
            .collect(),
        span: shift_span(style.span, offset),
    }
}

fn shift_c4_layout(layout: C4LayoutConfig, offset: usize) -> C4LayoutConfig {
    C4LayoutConfig {
        name: shift_spanned(layout.name, offset),
        fields: layout
            .fields
            .into_iter()
            .map(|field| shift_c4_arg(field, offset))
            .collect(),
        span: shift_span(layout.span, offset),
    }
}

fn shift_c4_arg(arg: C4CallArg, offset: usize) -> C4CallArg {
    C4CallArg {
        name: arg.name.map(|name| shift_spanned(name, offset)),
        value: shift_label(arg.value, offset),
        span: shift_span(arg.span, offset),
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

fn reject_reserved_flow_label(label: &Label) -> Result<(), ParseError> {
    if label.kind == LabelKind::Plain && label.text == "end" {
        return Err(ParseError {
            kind: ParseErrorKind::ReservedFlowNodeLabel,
            span: label.span,
        });
    }
    Ok(())
}

fn reject_unsupported_flowchart_config_directives(
    directives: &[MermaidDirective],
) -> Result<(), ParseError> {
    for directive in directives {
        reject_unsupported_flowchart_config_directive(directive)?;
    }
    Ok(())
}

fn reject_unsupported_flowchart_config_directive(
    directive: &MermaidDirective,
) -> Result<(), ParseError> {
    if is_unsupported_flowchart_config_directive(directive) {
        return Err(ParseError {
            kind: ParseErrorKind::UnsupportedMermaidConfig,
            span: directive.span,
        });
    }
    Ok(())
}

fn is_unsupported_flowchart_config_directive(directive: &MermaidDirective) -> bool {
    let key = directive.key.as_ref().map(|key| key.value.as_str());
    if matches!(
        key,
        Some("layout" | "look" | "theme" | "themeVariables" | "curve" | "elk" | "ELK")
    ) {
        return true;
    }
    if !matches!(key, Some("init" | "initialize")) {
        return false;
    }
    let raw = directive.raw.to_ascii_lowercase();
    ["layout", "look", "theme", "themevariables", "curve", "elk"]
        .iter()
        .any(|field| raw.contains(field))
}

fn reject_unsupported_state_config_directives(
    directives: &[MermaidDirective],
) -> Result<(), ParseError> {
    for directive in directives {
        reject_unsupported_state_config_directive(directive)?;
    }
    Ok(())
}

fn reject_unsupported_state_config_directive(
    directive: &MermaidDirective,
) -> Result<(), ParseError> {
    if is_unsupported_state_config_directive(directive) {
        return Err(ParseError {
            kind: ParseErrorKind::UnsupportedMermaidConfig,
            span: directive.span,
        });
    }
    Ok(())
}

fn is_unsupported_state_config_directive(directive: &MermaidDirective) -> bool {
    let key = directive.key.as_ref().map(|key| key.value.as_str());
    if matches!(key, Some("layout" | "look")) {
        return true;
    }
    if !matches!(key, Some("init" | "initialize")) {
        return false;
    }
    let raw = directive.raw.to_ascii_lowercase();
    ["layout", "look"].iter().any(|field| raw.contains(field))
}

fn apply_pie_config_directives(config: &mut PieConfig, directives: &[MermaidDirective]) {
    for directive in directives {
        apply_pie_config_directive(config, directive);
    }
}

fn apply_pie_config_directive(config: &mut PieConfig, directive: &MermaidDirective) {
    let key = directive.key.as_ref().map(|key| key.value.as_str());
    if !matches!(
        key,
        Some("init" | "initialize" | "config" | "pie" | "theme" | "themeVariables")
    ) {
        return;
    }
    let raw = if matches!(key, Some("pie")) {
        directive.raw.as_str()
    } else {
        config_object_value(&directive.raw, "pie").unwrap_or(&directive.raw)
    };
    if let Some(value) = config_number_value(raw, "textPosition")
        && let Some(position) = pie_text_position_milli(value)
    {
        config.text_position_milli = position;
    }
    if let Some(value) = config_string_value(raw, "legendPosition")
        && let Some(position) = PieLegendPosition::from_mermaid(value)
    {
        config.legend_position = position;
    }
}

fn config_object_value<'source>(source: &'source str, key: &str) -> Option<&'source str> {
    let start = config_value_start(source, key)?;
    let bytes = source.as_bytes();
    let mut cursor = skip_config_whitespace(source, start);
    if bytes.get(cursor).copied()? != b'{' {
        return None;
    }
    cursor += 1;
    let body_start = cursor;
    let mut depth = 1usize;
    let mut quote = None;
    while cursor < source.len() {
        let byte = bytes[cursor];
        if let Some(close) = quote {
            if byte == b'\\' {
                cursor = (cursor + 2).min(source.len());
                continue;
            }
            if byte == close {
                quote = None;
            }
            cursor += 1;
            continue;
        }
        match byte {
            b'\'' | b'"' => quote = Some(byte),
            b'{' => depth += 1,
            b'}' => {
                depth -= 1;
                if depth == 0 {
                    return Some(&source[body_start..cursor]);
                }
            }
            _ => {}
        }
        cursor += 1;
    }
    None
}

fn config_number_value<'source>(source: &'source str, key: &str) -> Option<&'source str> {
    let start = config_value_start(source, key)?;
    let end = source[start..]
        .find(|ch: char| !(ch.is_ascii_digit() || ch == '.'))
        .map_or(source.len(), |offset| start + offset);
    (end > start).then_some(&source[start..end])
}

fn config_string_value<'source>(source: &'source str, key: &str) -> Option<&'source str> {
    let start = config_value_start(source, key)?;
    let bytes = source.as_bytes();
    match bytes.get(start).copied()? {
        b'\'' | b'"' => {
            let quote = bytes[start];
            let value_start = start + 1;
            let mut cursor = value_start;
            while cursor < source.len() {
                if bytes[cursor] == b'\\' {
                    cursor = (cursor + 2).min(source.len());
                    continue;
                }
                if bytes[cursor] == quote {
                    return Some(&source[value_start..cursor]);
                }
                cursor += 1;
            }
            None
        }
        _ => {
            let end = source[start..]
                .find(|ch: char| !(ch.is_ascii_alphanumeric() || ch == '_' || ch == '-'))
                .map_or(source.len(), |offset| start + offset);
            (end > start).then_some(&source[start..end])
        }
    }
}

fn config_value_start(source: &str, key: &str) -> Option<usize> {
    for (start, _) in source.match_indices(key) {
        let before = source[..start].bytes().next_back();
        let after_index = start + key.len();
        let after = source.as_bytes().get(after_index).copied();
        let colon_start = if matches!(before, Some(b'\'' | b'"')) && after == before {
            after_index + 1
        } else {
            if before.is_some_and(is_identifier_byte) || after.is_some_and(is_identifier_byte) {
                continue;
            }
            after_index
        };
        let colon = skip_config_whitespace(source, colon_start);
        if source.as_bytes().get(colon).copied() != Some(b':') {
            continue;
        }
        return Some(skip_config_whitespace(source, colon + 1));
    }
    None
}

fn skip_config_whitespace(source: &str, mut cursor: usize) -> usize {
    while source
        .as_bytes()
        .get(cursor)
        .is_some_and(u8::is_ascii_whitespace)
    {
        cursor += 1;
    }
    cursor
}

fn is_identifier_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_'
}

fn pie_text_position_milli(value: &str) -> Option<u16> {
    let parsed = value.parse::<f64>().ok()?;
    (0.0..=1.0)
        .contains(&parsed)
        .then_some((parsed * 1000.0).round() as u16)
}

#[cfg(test)]
mod tests {
    use super::{
        FlowchartHeaderToken, FlowchartHeaderTokenKind, ParseError, ParseErrorKind, Parser,
    };
    use crate::ast::{
        ArchitectureAlignAxis, ArchitectureSide, ArrowHead, BlockArrowDirection, BlockShape,
        ClassMemberKind, ClassRelationshipLine, ClassRelationshipMarker, ClassStatement,
        DiagramKind, Direction, ErCardinality, ErStatement, EventModelingEntityType,
        FlowEdgeStroke, FlowShape, FlowStatement, FlowchartDirective, GanttTaskTag,
        GitGraphCommitKind, GitGraphOrientation, LabelKind, QuadrantAxisKind, RadarOptionKind,
        SequenceActivation, SequenceArrow, SequenceControlKind, SequenceNotePlacement,
        SequenceParticipantKind, SequenceStatement, Span, StateDirective, StateNodeKind,
        StateStatement, ZenUmlMessageKind,
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
    fn parses_gantt_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "gantt\ntitle Release Plan\nsection Build\nDesign API :done, api, 2026-01-01, 3d\nImplement core :active, core, after api, 5d",
        )
        .unwrap();

        let DiagramKind::Gantt(ast) = diagram.kind else {
            panic!("expected Gantt diagram");
        };
        assert_eq!(ast.title.unwrap().text, "Release Plan");
        assert_eq!(ast.tasks.len(), 2);
        assert_eq!(ast.tasks[0].section.as_ref().unwrap().text, "Build");
        assert_eq!(ast.tasks[0].id.as_ref().unwrap().value, "api");
        assert_eq!(ast.tasks[0].tags, vec![GanttTaskTag::Done]);
        assert_eq!(ast.tasks[1].tags, vec![GanttTaskTag::Active]);
        assert_eq!(ast.tasks[1].metadata[0].value, "after api");
    }

    #[test]
    fn parses_pie_document_to_diagram() {
        let diagram =
            Parser::parse_diagram("pie showData title Pets\n\"Dogs\" : 386\n\"Cats\" : 85.50")
                .unwrap();

        let DiagramKind::Pie(ast) = diagram.kind else {
            panic!("expected pie diagram");
        };
        assert!(ast.show_data);
        assert_eq!(ast.title.unwrap().text, "Pets");
        assert_eq!(ast.slices.len(), 2);
        assert_eq!(ast.slices[0].label.text, "Dogs");
        assert_eq!(ast.slices[0].value_units.value, 38_600);
        assert_eq!(ast.slices[1].value_units.value, 8_550);
    }

    #[test]
    fn parses_quadrant_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "quadrantChart\ntitle Priorities\nx-axis Low --> High\ny-axis Risk --> Reward\nquadrant-1 Invest\nAPI: [0.25, 0.75]\nclassDef focus fill:#f96,stroke:#333\nclass API focus",
        )
        .unwrap();

        let DiagramKind::Quadrant(ast) = diagram.kind else {
            panic!("expected quadrant diagram");
        };
        assert_eq!(ast.title.unwrap().text, "Priorities");
        assert_eq!(ast.x_axis.as_ref().unwrap().kind.value, QuadrantAxisKind::X);
        assert_eq!(ast.x_axis.as_ref().unwrap().start.text, "Low");
        assert_eq!(ast.y_axis.as_ref().unwrap().end.text, "Reward");
        assert_eq!(ast.quadrants[0].index.value, 1);
        assert_eq!(ast.quadrants[0].label.text, "Invest");
        assert_eq!(ast.points[0].label.text, "API");
        assert_eq!(ast.points[0].x.value, 250);
        assert_eq!(ast.points[0].y.value, 750);
        assert_eq!(ast.classes.len(), 1);
    }

    #[test]
    fn parses_zenuml_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "zenuml\ntitle Calls\n@Actor Alice\nService as API\nAlice->Service.fetch(id) {\n  if cache miss {\n    new Record\n  }\n  return done\n}",
        )
        .unwrap();

        let DiagramKind::ZenUml(ast) = diagram.kind else {
            panic!("expected ZenUML diagram");
        };
        assert_eq!(ast.title.unwrap().text, "Calls");
        assert_eq!(ast.participants[0].id.value, "Alice");
        assert_eq!(
            ast.participants[0].annotator.as_ref().unwrap().value,
            "Actor"
        );
        assert_eq!(ast.participants[1].label.as_ref().unwrap().text, "API");
        assert_eq!(ast.messages[0].from.as_ref().unwrap().value, "Alice");
        assert_eq!(ast.messages[0].to.value, "Service");
        assert_eq!(ast.messages[0].label.as_ref().unwrap().text, "fetch(id)");
        assert_eq!(ast.messages[1].kind.value, ZenUmlMessageKind::Create);
        assert_eq!(ast.fragments[0].label.as_ref().unwrap().text, "cache miss");
    }

    #[test]
    fn parses_sankey_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "sankey-beta\n\"North America\",Pipeline,12.5\nPipeline,\"Closed, Won\",9",
        )
        .unwrap();

        let DiagramKind::Sankey(ast) = diagram.kind else {
            panic!("expected Sankey diagram");
        };
        assert_eq!(ast.links.len(), 2);
        assert_eq!(ast.links[0].source.text, "North America");
        assert_eq!(ast.links[0].target.text, "Pipeline");
        assert_eq!(ast.links[0].value_units.value, 1250);
        assert_eq!(ast.links[1].target.text, "Closed, Won");
    }

    #[test]
    fn parses_xy_chart_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "xychart-beta\ntitle Sales\nx-axis Month [Jan, Feb]\ny-axis Revenue 0 --> 100\nbar [42, 58]\nline [35, 60]",
        )
        .unwrap();

        let DiagramKind::XyChart(ast) = diagram.kind else {
            panic!("expected XY Chart diagram");
        };
        assert_eq!(ast.title.unwrap().text, "Sales");
        assert_eq!(
            ast.x_axis.as_ref().unwrap().title.as_ref().unwrap().text,
            "Month"
        );
        assert_eq!(
            ast.y_axis.as_ref().unwrap().title.as_ref().unwrap().text,
            "Revenue"
        );
        assert_eq!(ast.series.len(), 2);
        assert_eq!(ast.series[0].values[0].value, 4_200);
        assert_eq!(ast.series[1].value_texts[1].value, "60");
    }

    #[test]
    fn parses_block_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "block columns 3\nA[Frontend] arrow<[\"go\"]>(right) B:2\nblock:Backend:2 columns 1\nAPI\nDB[(Database)]\nend\nA --> B\nstyle B fill:#969,stroke:#333\nclassDef hot fill:#f96\nclass A hot",
        )
        .unwrap();

        let DiagramKind::Block(ast) = diagram.kind else {
            panic!("expected Block diagram");
        };
        assert_eq!(ast.header.columns.unwrap().value, 3);
        assert_eq!(ast.blocks.len(), 5);
        assert_eq!(ast.blocks[0].id.value, "A");
        assert_eq!(ast.blocks[0].label.as_ref().unwrap().text, "Frontend");
        assert!(matches!(
            ast.blocks[0].shape.value,
            BlockShape::Flow(FlowShape::Rectangle)
        ));
        assert_eq!(ast.blocks[1].width.value, 1);
        let BlockShape::Arrow(directions) = &ast.blocks[1].shape.value else {
            panic!("expected block arrow");
        };
        assert_eq!(directions[0].value, BlockArrowDirection::Right);
        assert_eq!(ast.blocks[2].id.value, "B");
        assert_eq!(ast.blocks[2].width.value, 2);
        assert_eq!(ast.blocks[3].id.value, "API");
        assert_eq!(ast.edges[0].from.value, "A");
        assert_eq!(ast.edges[0].to.value, "B");
        assert_eq!(ast.styles[0].target.value, "B");
        assert_eq!(ast.classes.len(), 1);
    }

    #[test]
    fn parses_packet_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "packet\ntitle UDP Packet\n+16: \"Source Port\" %% inline\n+16: \"Destination Port\"\n32-47: \"Length\"\n48: \"Flag\"",
        )
        .unwrap();

        let DiagramKind::Packet(ast) = diagram.kind else {
            panic!("expected Packet diagram");
        };
        assert_eq!(ast.title.unwrap().text, "UDP Packet");
        assert_eq!(ast.fields.len(), 4);
        assert_eq!(ast.fields[0].range.start.value, 0);
        assert_eq!(ast.fields[0].range.end.value, 15);
        assert_eq!(ast.fields[1].range.start.value, 16);
        assert_eq!(ast.fields[1].range.end.value, 31);
        assert_eq!(ast.fields[2].range.start.value, 32);
        assert_eq!(ast.fields[2].range.end.value, 47);
        assert_eq!(ast.fields[3].range.start.value, 48);
        assert_eq!(ast.fields[3].range.end.value, 48);
        assert_eq!(ast.fields[0].label.text, "Source Port");
    }

    #[test]
    fn parses_kanban_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "kanban\n  todo[Todo]\n    docs[Create Documentation]\n    bug[Fix Login]@{ ticket: MC-2038, assigned: 'K.Sveidqvist', priority: 'High' }\n  [Done]\n    [Ship release]",
        )
        .unwrap();

        let DiagramKind::Kanban(ast) = diagram.kind else {
            panic!("expected Kanban diagram");
        };
        assert_eq!(ast.columns.len(), 2);
        assert_eq!(ast.columns[0].id.as_ref().unwrap().value, "todo");
        assert_eq!(ast.columns[0].title.text, "Todo");
        assert_eq!(ast.columns[0].tasks.len(), 2);
        assert_eq!(ast.columns[0].tasks[0].id.as_ref().unwrap().value, "docs");
        assert_eq!(ast.columns[0].tasks[0].label.text, "Create Documentation");
        assert_eq!(ast.columns[0].tasks[1].metadata.len(), 3);
        assert_eq!(ast.columns[0].tasks[1].metadata[0].key.value, "ticket");
        assert_eq!(
            ast.columns[0].tasks[1].metadata[1].value.text,
            "K.Sveidqvist"
        );
        assert_eq!(ast.columns[1].id, None);
        assert_eq!(ast.columns[1].title.text, "Done");
        assert_eq!(ast.columns[1].tasks[0].label.text, "Ship release");
    }

    #[test]
    fn parses_architecture_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "architecture-beta\ngroup api(cloud)[API]\nservice gateway(server)[Gateway] in api\nservice db(database)[Database]\njunction join in api\ngateway:R --> L:db\nalign row gateway join",
        )
        .unwrap();

        let DiagramKind::Architecture(ast) = diagram.kind else {
            panic!("expected Architecture diagram");
        };
        assert_eq!(ast.groups.len(), 1);
        assert_eq!(ast.groups[0].id.value, "api");
        assert_eq!(ast.groups[0].icon.as_ref().unwrap().text, "cloud");
        assert_eq!(ast.groups[0].title.as_ref().unwrap().text, "API");
        assert_eq!(ast.services.len(), 2);
        assert_eq!(ast.services[0].parent.as_ref().unwrap().value, "api");
        assert_eq!(ast.junctions[0].id.value, "join");
        assert_eq!(ast.edges.len(), 1);
        assert!(ast.edges[0].arrow_end);
        assert_eq!(ast.edges[0].from.side.value, ArchitectureSide::Right);
        assert_eq!(ast.edges[0].to.side.value, ArchitectureSide::Left);
        assert_eq!(ast.alignments[0].axis.value, ArchitectureAlignAxis::Row);
        assert_eq!(ast.alignments[0].members.len(), 2);
    }

    #[test]
    fn parses_radar_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            r#"radar-beta
title Skill Matrix
axis speed["Speed"], quality["Quality"], docs
curve teamA["Team A"]{speed: 80, quality: 70, docs: 60}
curve teamB{40, 90, 50}
showLegend true
max 100
min 0
graticule polygon
ticks 4"#,
        )
        .unwrap();

        let DiagramKind::Radar(ast) = diagram.kind else {
            panic!("expected Radar diagram");
        };
        assert_eq!(ast.title.unwrap().text, "Skill Matrix");
        assert_eq!(ast.axes.len(), 3);
        assert_eq!(ast.axes[0].id.value, "speed");
        assert_eq!(ast.axes[0].label.as_ref().unwrap().text, "Speed");
        assert_eq!(ast.curves.len(), 2);
        assert_eq!(ast.curves[0].label.as_ref().unwrap().text, "Team A");
        assert_eq!(
            ast.curves[0].values[0].axis.as_ref().unwrap().value,
            "speed"
        );
        assert_eq!(ast.curves[1].values[1].value.value, "90");
        assert_eq!(ast.options.len(), 5);
        assert_eq!(ast.options[3].kind.value, RadarOptionKind::Graticule);
    }

    #[test]
    fn parses_mindmap_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "mindmap\n  Root\n    Branch A\n      Leaf A1\n    Branch B\n      ::icon(fa fa-code)",
        )
        .unwrap();

        let DiagramKind::Mindmap(ast) = diagram.kind else {
            panic!("expected mindmap diagram");
        };
        assert_eq!(ast.roots.len(), 1);
        assert_eq!(ast.roots[0].label.text, "Root");
        assert_eq!(ast.roots[0].children.len(), 2);
        assert_eq!(ast.roots[0].children[0].children[0].label.text, "Leaf A1");
        assert_eq!(
            ast.roots[0].children[1].icon.as_ref().unwrap().value,
            "fa fa-code",
        );
    }

    #[test]
    fn parses_journey_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "journey\ntitle Working Day\nsection Go to work\nMake tea: 5: Me, Kettle\nDo work: 1: Me",
        )
        .unwrap();

        let DiagramKind::Journey(ast) = diagram.kind else {
            panic!("expected Journey diagram");
        };
        assert_eq!(ast.title.unwrap().text, "Working Day");
        assert_eq!(ast.tasks.len(), 2);
        assert_eq!(ast.tasks[0].label.text, "Make tea");
        assert_eq!(ast.tasks[0].section.as_ref().unwrap().text, "Go to work");
        assert_eq!(ast.tasks[0].score.value, 5);
        assert_eq!(ast.tasks[0].actors[0].value, "Me");
        assert_eq!(ast.tasks[0].actors[1].value, "Kettle");
        assert_eq!(ast.tasks[1].score.value, 1);
    }

    #[test]
    fn parses_gitgraph_document_to_diagram() {
        assert_eq!(
            Parser::parse_gitgraph_header("gitGraph:")
                .unwrap()
                .orientation
                .value,
            GitGraphOrientation::LeftRight,
        );
        let diagram = Parser::parse_diagram(
            r#"gitGraph TB:
commit id: "base"
branch develop order: 2
commit id: "feat" type: HIGHLIGHT tag: "v1"
checkout main
merge develop id: "merge" type: REVERSE
cherry-pick id: "feat" parent: "base""#,
        )
        .unwrap();

        let DiagramKind::GitGraph(ast) = diagram.kind else {
            panic!("expected GitGraph diagram");
        };
        assert_eq!(ast.header.orientation.value, GitGraphOrientation::TopBottom);
        assert_eq!(ast.commits.len(), 2);
        assert_eq!(ast.commits[1].id.as_ref().unwrap().value, "feat");
        assert_eq!(ast.commits[1].kind.value, GitGraphCommitKind::Highlight);
        assert_eq!(ast.commits[1].tag.as_ref().unwrap().value, "v1");
        assert_eq!(ast.branches[0].name.value, "develop");
        assert_eq!(ast.branches[0].order.unwrap().value, 2);
        assert_eq!(ast.merges[0].branch.value, "develop");
        assert_eq!(ast.merges[0].kind.value, GitGraphCommitKind::Reverse);
        assert_eq!(ast.cherry_picks[0].id.value, "feat");
        assert_eq!(ast.cherry_picks[0].parent.as_ref().unwrap().value, "base");
    }

    #[test]
    fn parses_timeline_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "timeline\ntitle Release Train\nsection Alpha\n2024 Q1 : Design : Prototype\n        : Validate\nsection Beta\n2024 Q2 : Launch",
        )
        .unwrap();

        let DiagramKind::Timeline(ast) = diagram.kind else {
            panic!("expected Timeline diagram");
        };
        assert_eq!(ast.title.unwrap().text, "Release Train");
        assert_eq!(ast.periods.len(), 2);
        assert_eq!(ast.periods[0].label.text, "2024 Q1");
        assert_eq!(ast.periods[0].section.as_ref().unwrap().text, "Alpha");
        assert_eq!(ast.periods[0].events[0].text, "Design");
        assert_eq!(ast.periods[0].events[1].text, "Prototype");
        assert_eq!(ast.periods[0].events[2].text, "Validate");
        assert_eq!(ast.periods[1].section.as_ref().unwrap().text, "Beta");
    }

    #[test]
    fn parses_event_modeling_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "eventmodeling\ntf 01 ui CartUI\ntimeframe 02 command AddItem [[AddItem01]]\ntf 03 evt ItemAdded `json`{ description: string }\ndata AddItem01 { description: 'jack' }",
        )
        .unwrap();

        let DiagramKind::EventModeling(ast) = diagram.kind else {
            panic!("expected Event Modeling diagram");
        };
        assert_eq!(ast.timeframes.len(), 3);
        assert_eq!(ast.timeframes[0].entity.value, "CartUI");
        assert_eq!(
            ast.timeframes[1].entity_type.value,
            EventModelingEntityType::Command
        );
        assert_eq!(
            ast.timeframes[1].data_ref.as_ref().unwrap().value,
            "AddItem01"
        );
        assert_eq!(
            ast.timeframes[2]
                .data
                .as_ref()
                .unwrap()
                .ty
                .as_ref()
                .unwrap()
                .value,
            "json"
        );
        assert_eq!(ast.data_blocks[0].id.value, "AddItem01");
    }

    #[test]
    fn parses_treemap_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "treemap-beta\n\"Sales\":::region\n  \"Product A\": 40\n  \"Product B\": 60:::focus\nclassDef region fill:#ddeeff",
        )
        .unwrap();

        let DiagramKind::Treemap(ast) = diagram.kind else {
            panic!("expected Treemap diagram");
        };
        assert_eq!(ast.roots.len(), 1);
        assert_eq!(ast.roots[0].label.text, "Sales");
        assert_eq!(ast.roots[0].classes[0].value, "region");
        assert_eq!(ast.roots[0].children.len(), 2);
        assert_eq!(ast.roots[0].children[0].value.as_ref().unwrap().value, "40");
        assert_eq!(ast.roots[0].children[1].classes[0].value, "focus");
        assert_eq!(ast.classes.len(), 1);
    }

    #[test]
    fn parses_venn_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "venn-beta\ntitle \"Team overlap\"\nset A[\"Alpha\"]:20\ntext A1[\"React\"]\nset B[\"Beta\"]:12\nunion A,B[\"AB\"]:3\ntext AB1[\"OpenAPI\"]\nstyle A,B color:#333",
        )
        .unwrap();

        let DiagramKind::Venn(ast) = diagram.kind else {
            panic!("expected Venn diagram");
        };
        assert_eq!(ast.title.unwrap().text, "Team overlap");
        assert_eq!(ast.sets.len(), 2);
        assert_eq!(ast.sets[0].label.as_ref().unwrap().text, "Alpha");
        assert_eq!(ast.sets[0].texts[0].label.as_ref().unwrap().text, "React");
        assert_eq!(ast.unions[0].members[1].value, "B");
        assert_eq!(
            ast.unions[0].texts[0].label.as_ref().unwrap().text,
            "OpenAPI"
        );
        assert_eq!(ast.styles[0].targets.len(), 2);
    }

    #[test]
    fn parses_ishikawa_document_to_diagram() {
        let diagram = Parser::parse_diagram(
            "ishikawa-beta\nBlurry Photo\n  Process\n    Out of focus\n  Equipment\n    Lens\n      Dirty lens",
        )
        .unwrap();

        let DiagramKind::Ishikawa(ast) = diagram.kind else {
            panic!("expected Ishikawa diagram");
        };
        assert_eq!(ast.event.text, "Blurry Photo");
        assert_eq!(ast.causes.len(), 2);
        assert_eq!(ast.causes[0].label.text, "Process");
        assert_eq!(ast.causes[0].causes[0].label.text, "Out of focus");
        assert_eq!(ast.causes[1].causes[0].causes[0].label.text, "Dirty lens");
    }

    #[test]
    fn rejects_unsupported_mermaid_roots_from_coverage_matrix() {
        let cases = [("Wardley", "wardley-beta"), ("TreeView", "treeView-beta")];

        for (name, source) in cases {
            let error = Parser::parse_diagram(source).unwrap_err();

            assert_eq!(error.kind, ParseErrorKind::ExpectedDiagramHeader, "{name}");
            assert_eq!(error.span, Span::new(0, source.len()), "{name}");
        }
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
    fn rejects_unquoted_reserved_end_flow_label() {
        assert_eq!(
            Parser::parse_flow_node("A[end]").unwrap_err(),
            ParseError {
                kind: ParseErrorKind::ReservedFlowNodeLabel,
                span: Span::new(2, 5),
            },
        );
        assert_eq!(
            Parser::parse_flow_node(r#"A["end"]"#)
                .unwrap()
                .label
                .unwrap()
                .text,
            "end",
        );
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
    fn parses_sequence_message_activation_shorthand() {
        let start = Parser::parse_sequence_statement("Alice->>+Bob: start").unwrap();
        let end = Parser::parse_sequence_statement("Bob-->>-Alice: done").unwrap();

        let SequenceStatement::Message(start) = start else {
            panic!("expected message statement");
        };
        let SequenceStatement::Message(end) = end else {
            panic!("expected message statement");
        };
        assert_eq!(start.activation.unwrap().value, SequenceActivation::Start);
        assert_eq!(start.to.value, "Bob");
        assert_eq!(end.activation.unwrap().value, SequenceActivation::End);
        assert_eq!(end.to.value, "Alice");
    }

    #[test]
    fn parses_sequence_autonumber() {
        let bare = Parser::parse_sequence_statement("autonumber").unwrap();
        let configured = Parser::parse_sequence_statement("autonumber 10.5 0.25").unwrap();

        let SequenceStatement::AutoNumber(bare) = bare else {
            panic!("expected autonumber statement");
        };
        let SequenceStatement::AutoNumber(configured) = configured else {
            panic!("expected autonumber statement");
        };
        assert!(bare.start.is_none());
        assert_eq!(configured.start.unwrap().value, "10.5");
        assert_eq!(configured.step.unwrap().value, "0.25");
        assert_eq!(
            Parser::parse_sequence_statement("autonumber 1.234")
                .unwrap_err()
                .kind,
            ParseErrorKind::UnknownSequenceStatement,
        );
    }

    #[test]
    fn parses_sequence_activation_directives() {
        let activate = Parser::parse_sequence_statement("activate Bob").unwrap();
        let deactivate = Parser::parse_sequence_statement("deactivate Bob").unwrap();

        let SequenceStatement::ActivationStart(activate) = activate else {
            panic!("expected activation start");
        };
        let SequenceStatement::ActivationEnd(deactivate) = deactivate else {
            panic!("expected activation end");
        };
        assert_eq!(activate.value, "Bob");
        assert_eq!(deactivate.value, "Bob");
    }

    #[test]
    fn parses_sequence_create_destroy_and_box() {
        let create =
            Parser::parse_sequence_statement("create participant Bot as Worker Bot").unwrap();
        let destroy = Parser::parse_sequence_statement("destroy Bot").unwrap();
        let sequence_box = Parser::parse_sequence_statement("box Aqua Workers").unwrap();

        let SequenceStatement::Create(create) = create else {
            panic!("expected create statement");
        };
        let SequenceStatement::Destroy(destroy) = destroy else {
            panic!("expected destroy statement");
        };
        let SequenceStatement::Box(sequence_box) = sequence_box else {
            panic!("expected box statement");
        };
        assert_eq!(create.participant.id.value, "Bot");
        assert_eq!(create.participant.alias.unwrap().text, "Worker Bot");
        assert_eq!(destroy.participant.value, "Bot");
        assert_eq!(sequence_box.label.unwrap().text, "Aqua Workers");
    }

    #[test]
    fn parses_sequence_box_participants_in_document() {
        let ast = Parser::parse_sequence(
            "sequenceDiagram\nbox Workers\nparticipant A\nparticipant B\nend\nA->>B: hi",
        )
        .unwrap();

        assert_eq!(ast.boxes.len(), 1);
        assert_eq!(ast.boxes[0].participants.len(), 2);
        assert_eq!(ast.boxes[0].participants[0].value, "A");
        assert_eq!(ast.boxes[0].participants[1].value, "B");
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
            ("critical Commit", SequenceControlKind::Critical),
            ("break Failure", SequenceControlKind::Break),
            ("rect rgba(0, 0, 255, .1)", SequenceControlKind::Rect),
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
