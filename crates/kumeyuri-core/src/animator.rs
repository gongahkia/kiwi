use crate::ast::{
    C4Statement, ClassAst, ClassStatement, Diagram, DiagramKind, ErAst, ErStatement, FlowStatement,
    FlowchartAst, GanttAst, GanttStatement, GitGraphAst, GitGraphStatement, JourneyAst,
    JourneyStatement, MermaidDirective, MindmapAst, MindmapStatement, PieAst, PieStatement,
    RequirementStatement, SequenceAst, SequenceStatement, StateAst, StateStatement, TimelineAst,
    TimelineStatement,
};
use crate::frame::{Frame, FrameRegion, KeyFrameMarker, KeyFrameMarkerKind, StaticFrameRenderer};
use crate::layout::{
    ClassLayout, ClassLayoutEngine, ErLayoutEngine, FlowLayout, FlowLayoutEngine,
    GanttLayoutEngine, GitGraphLayoutEngine, JourneyLayoutEngine, MindmapLayoutEngine, PieLayout,
    PieLayoutEngine, Point, PositionedClassNode, PositionedClassRelationship, PositionedFlowEdge,
    PositionedFlowNode, PositionedGanttTask, PositionedGitGraphCommit, PositionedJourneyTask,
    PositionedMindmapNode, PositionedSequenceMessage, PositionedSequenceParticipant,
    PositionedTimelinePeriod, SequenceLayout, SequenceLayoutEngine, StateLayout, StateLayoutEngine,
    TimelineLayoutEngine,
};
use std::collections::VecDeque;
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Animator;

impl Animator {
    #[must_use]
    pub fn sequence_playback(ast: &SequenceAst) -> Timeline {
        SequencePlaybackAnimator::default().animate(ast)
    }

    #[must_use]
    pub fn flowchart_trace(ast: &FlowchartAst) -> Timeline {
        FlowchartTraceAnimator::default().animate(ast)
    }

    #[must_use]
    pub fn state_transitions(ast: &StateAst) -> Timeline {
        StateTransitionAnimator::default().animate(ast)
    }

    #[must_use]
    pub fn class_trace(ast: &ClassAst) -> Timeline {
        ClassRelationshipAnimator::default().animate(ast)
    }

    #[must_use]
    pub fn er_trace(ast: &ErAst) -> Timeline {
        ErRelationshipAnimator::default().animate(ast)
    }

    #[must_use]
    pub fn gantt_sweep(ast: &GanttAst) -> Timeline {
        GanttSweepAnimator::default().animate(ast)
    }

    #[must_use]
    pub fn pie_growth(ast: &PieAst) -> Timeline {
        PieSliceGrowthAnimator::default().animate(ast)
    }

    #[must_use]
    pub fn mindmap_expand(ast: &MindmapAst) -> Timeline {
        MindmapExpandAnimator::default().animate(ast)
    }

    #[must_use]
    pub fn journey_trace(ast: &JourneyAst) -> Timeline {
        JourneyTraceAnimator::default().animate(ast)
    }

    #[must_use]
    pub fn gitgraph_trace(ast: &GitGraphAst) -> Timeline {
        GitGraphTraceAnimator::default().animate(ast)
    }

    #[must_use]
    pub fn timeline_reveal(ast: &TimelineAst) -> Timeline {
        TimelineRevealAnimator::default().animate(ast)
    }

    pub fn animate_diagram(diagram: &Diagram) -> Result<Timeline, AnimationConfigParseError> {
        Self::animate_diagram_with_options(diagram, AnimationOptions::default())
    }

    pub fn animate_diagram_with_options(
        diagram: &Diagram,
        options: AnimationOptions,
    ) -> Result<Timeline, AnimationConfigParseError> {
        Self::animate_diagram_with_options_and_renderer(
            diagram,
            options,
            StaticFrameRenderer::default(),
        )
    }

    pub fn animate_diagram_with_options_and_renderer(
        diagram: &Diagram,
        options: AnimationOptions,
        renderer: StaticFrameRenderer,
    ) -> Result<Timeline, AnimationConfigParseError> {
        let config = AnimationConfig::from_diagram(diagram)?;
        let mode = config.as_ref().map_or_else(
            || default_animation_mode(&diagram.kind),
            |config| config.mode,
        );
        let speed = options.speed().unwrap_or_else(|| {
            config
                .as_ref()
                .map_or(AnimationConfig::DEFAULT_SPEED, |config| config.speed)
        });
        if !is_valid_animation_speed(speed) {
            return Err(AnimationConfigParseError::InvalidSpeed(speed.to_string()));
        }
        let repeat = options
            .repeat()
            .unwrap_or_else(|| config.as_ref().is_some_and(|config| config.repeat));

        let timeline = match (&diagram.kind, mode) {
            (_, AnimationMode::None) => static_timeline(diagram, renderer),
            (DiagramKind::Sequence(ast), AnimationMode::Playback) => SequencePlaybackAnimator::new(
                scaled_duration(SequencePlaybackAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::Flowchart(ast), AnimationMode::Trace) => FlowchartTraceAnimator::new(
                scaled_duration(FlowchartTraceAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::State(ast), AnimationMode::Transitions) => StateTransitionAnimator::new(
                scaled_duration(StateTransitionAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::Class(ast), AnimationMode::Trace) => ClassRelationshipAnimator::new(
                scaled_duration(ClassRelationshipAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::Er(ast), AnimationMode::Trace) => ErRelationshipAnimator::new(
                scaled_duration(ErRelationshipAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::Gantt(ast), AnimationMode::Trace) => GanttSweepAnimator::new(
                scaled_duration(GanttSweepAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::Pie(ast), AnimationMode::Trace) => PieSliceGrowthAnimator::new(
                scaled_duration(PieSliceGrowthAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::Mindmap(ast), AnimationMode::Trace) => MindmapExpandAnimator::new(
                scaled_duration(MindmapExpandAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::Journey(ast), AnimationMode::Trace) => JourneyTraceAnimator::new(
                scaled_duration(JourneyTraceAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::GitGraph(ast), AnimationMode::Trace) => GitGraphTraceAnimator::new(
                scaled_duration(GitGraphTraceAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::Timeline(ast), AnimationMode::Trace) => TimelineRevealAnimator::new(
                scaled_duration(TimelineRevealAnimator::default_frame_duration(), speed),
            )
            .animate_with_renderer(ast, renderer),
            (DiagramKind::Requirement(_), _) => static_timeline(diagram, renderer),
            (DiagramKind::C4(_), _) => static_timeline(diagram, renderer),
            (kind, mode) => {
                return Err(AnimationConfigParseError::UnsupportedMode {
                    mode,
                    diagram: AnimationDiagramKind::from(kind),
                });
            }
        };

        Ok(timeline.with_repeat(repeat))
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct AnimationOptions {
    speed: Option<f32>,
    repeat: Option<bool>,
}

impl AnimationOptions {
    pub fn new(speed: Option<f32>, repeat: Option<bool>) -> Result<Self, AnimationConfigError> {
        if speed.is_some_and(|speed| !is_valid_animation_speed(speed)) {
            return Err(AnimationConfigError::InvalidSpeed);
        }
        Ok(Self { speed, repeat })
    }

    #[must_use]
    pub const fn speed(self) -> Option<f32> {
        self.speed
    }

    #[must_use]
    pub const fn repeat(self) -> Option<bool> {
        self.repeat
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AnimationConfig {
    pub mode: AnimationMode,
    pub speed: f32,
    pub repeat: bool,
    pub easing: AnimationEasing,
}

impl Default for AnimationConfig {
    fn default() -> Self {
        Self {
            mode: AnimationMode::None,
            speed: Self::DEFAULT_SPEED,
            repeat: false,
            easing: AnimationEasing::Linear,
        }
    }
}

impl AnimationConfig {
    pub const DEFAULT_SPEED: f32 = 1.0;

    pub fn from_diagram(diagram: &Diagram) -> Result<Option<Self>, AnimationConfigParseError> {
        let mut config = None;
        apply_animation_directives(&diagram.directives, &mut config)?;
        match &diagram.kind {
            DiagramKind::Flowchart(ast) => {
                for statement in &ast.statements {
                    apply_flow_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::Sequence(ast) => {
                for statement in &ast.statements {
                    apply_sequence_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::State(ast) => {
                for statement in &ast.statements {
                    apply_state_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::Class(ast) => {
                for statement in &ast.statements {
                    apply_class_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::Er(ast) => {
                for statement in &ast.statements {
                    apply_er_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::Gantt(ast) => {
                for statement in &ast.statements {
                    apply_gantt_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::Pie(ast) => {
                for statement in &ast.statements {
                    apply_pie_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::Mindmap(ast) => {
                for statement in &ast.statements {
                    apply_mindmap_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::Journey(ast) => {
                for statement in &ast.statements {
                    apply_journey_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::GitGraph(ast) => {
                for statement in &ast.statements {
                    apply_gitgraph_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::Timeline(ast) => {
                for statement in &ast.statements {
                    apply_timeline_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::Requirement(ast) => {
                for statement in &ast.statements {
                    apply_requirement_animation_directives(statement, &mut config)?;
                }
            }
            DiagramKind::C4(ast) => {
                for statement in &ast.statements {
                    apply_c4_animation_directives(statement, &mut config)?;
                }
            }
        }
        Ok(config)
    }

    pub fn from_directive(
        directive: &MermaidDirective,
    ) -> Result<Option<Self>, AnimationConfigParseError> {
        if directive
            .key
            .as_ref()
            .is_none_or(|key| key.value != "animate")
        {
            return Ok(None);
        }
        parse_animation_directive(&directive.raw).map(Some)
    }

    pub fn new(
        mode: AnimationMode,
        speed: f32,
        repeat: bool,
        easing: AnimationEasing,
    ) -> Result<Self, AnimationConfigError> {
        if !is_valid_animation_speed(speed) {
            return Err(AnimationConfigError::InvalidSpeed);
        }
        Ok(Self {
            mode,
            speed,
            repeat,
            easing,
        })
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum AnimationMode {
    Playback,
    Trace,
    Transitions,
    #[default]
    None,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum AnimationEasing {
    #[default]
    Linear,
    Ease,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AnimationConfigError {
    InvalidSpeed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AnimationConfigParseError {
    MissingAnimate,
    UnknownField(String),
    UnknownMode(String),
    UnknownEasing(String),
    InvalidSpeed(String),
    InvalidLoop(String),
    UnsupportedMode {
        mode: AnimationMode,
        diagram: AnimationDiagramKind,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AnimationDiagramKind {
    Flowchart,
    Sequence,
    State,
    Class,
    Er,
    Gantt,
    Pie,
    Mindmap,
    Journey,
    GitGraph,
    Timeline,
    Requirement,
    C4,
}

impl From<&DiagramKind> for AnimationDiagramKind {
    fn from(kind: &DiagramKind) -> Self {
        match kind {
            DiagramKind::Flowchart(_) => Self::Flowchart,
            DiagramKind::Sequence(_) => Self::Sequence,
            DiagramKind::State(_) => Self::State,
            DiagramKind::Class(_) => Self::Class,
            DiagramKind::Er(_) => Self::Er,
            DiagramKind::Gantt(_) => Self::Gantt,
            DiagramKind::Pie(_) => Self::Pie,
            DiagramKind::Mindmap(_) => Self::Mindmap,
            DiagramKind::Journey(_) => Self::Journey,
            DiagramKind::GitGraph(_) => Self::GitGraph,
            DiagramKind::Timeline(_) => Self::Timeline,
            DiagramKind::Requirement(_) => Self::Requirement,
            DiagramKind::C4(_) => Self::C4,
        }
    }
}

fn is_valid_animation_speed(speed: f32) -> bool {
    speed.is_finite() && speed > 0.0
}

fn apply_animation_directives(
    directives: &[MermaidDirective],
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    for directive in directives {
        if let Some(next) = AnimationConfig::from_directive(directive)? {
            *config = Some(next);
        }
    }
    Ok(())
}

fn apply_flow_animation_directives(
    statement: &FlowStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        FlowStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        FlowStatement::Subgraph(subgraph) => {
            for statement in &subgraph.statements {
                apply_flow_animation_directives(statement, config)?;
            }
        }
        FlowStatement::Node(_)
        | FlowStatement::Edge(_)
        | FlowStatement::ClassDef(_)
        | FlowStatement::ClassApply(_)
        | FlowStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_sequence_animation_directives(
    statement: &SequenceStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        SequenceStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        SequenceStatement::Control(control) => {
            for statement in &control.statements {
                apply_sequence_animation_directives(statement, config)?;
            }
        }
        SequenceStatement::Participant(_)
        | SequenceStatement::Create(_)
        | SequenceStatement::Destroy(_)
        | SequenceStatement::Box(_)
        | SequenceStatement::Message(_)
        | SequenceStatement::ActivationStart(_)
        | SequenceStatement::ActivationEnd(_)
        | SequenceStatement::Note(_)
        | SequenceStatement::AutoNumber(_)
        | SequenceStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_state_animation_directives(
    statement: &StateStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        StateStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        StateStatement::Composite(state) => {
            for statement in &state.children {
                apply_state_animation_directives(statement, config)?;
            }
        }
        StateStatement::State(_)
        | StateStatement::Transition(_)
        | StateStatement::ClassDef(_)
        | StateStatement::ClassApply(_)
        | StateStatement::Direction(_)
        | StateStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_class_animation_directives(
    statement: &ClassStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        ClassStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        ClassStatement::Class(_)
        | ClassStatement::Member(_)
        | ClassStatement::Relationship(_)
        | ClassStatement::Direction(_)
        | ClassStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_er_animation_directives(
    statement: &ErStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        ErStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        ErStatement::Entity(_) | ErStatement::Relationship(_) | ErStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_gantt_animation_directives(
    statement: &GanttStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        GanttStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        GanttStatement::Title(_)
        | GanttStatement::DateFormat(_)
        | GanttStatement::AxisFormat(_)
        | GanttStatement::Section(_)
        | GanttStatement::Task(_)
        | GanttStatement::Config(_)
        | GanttStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_pie_animation_directives(
    statement: &PieStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        PieStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        PieStatement::Title(_) | PieStatement::Slice(_) | PieStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_mindmap_animation_directives(
    statement: &MindmapStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        MindmapStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        MindmapStatement::Node(_) | MindmapStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_journey_animation_directives(
    statement: &JourneyStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        JourneyStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        JourneyStatement::Title(_)
        | JourneyStatement::Section(_)
        | JourneyStatement::Task(_)
        | JourneyStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_gitgraph_animation_directives(
    statement: &GitGraphStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        GitGraphStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        GitGraphStatement::Commit(_)
        | GitGraphStatement::Branch(_)
        | GitGraphStatement::Checkout(_)
        | GitGraphStatement::Merge(_)
        | GitGraphStatement::CherryPick(_)
        | GitGraphStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_timeline_animation_directives(
    statement: &TimelineStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        TimelineStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        TimelineStatement::Title(_)
        | TimelineStatement::Section(_)
        | TimelineStatement::Period(_)
        | TimelineStatement::Event(_)
        | TimelineStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_requirement_animation_directives(
    statement: &RequirementStatement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        RequirementStatement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        RequirementStatement::Requirement(_)
        | RequirementStatement::Element(_)
        | RequirementStatement::Relationship(_)
        | RequirementStatement::Direction(_)
        | RequirementStatement::Style(_)
        | RequirementStatement::ClassDef(_)
        | RequirementStatement::ClassApply(_)
        | RequirementStatement::Comment(_) => {}
    }
    Ok(())
}

fn apply_c4_animation_directives(
    statement: &C4Statement,
    config: &mut Option<AnimationConfig>,
) -> Result<(), AnimationConfigParseError> {
    match statement {
        C4Statement::Directive(directive) => {
            if let Some(next) = AnimationConfig::from_directive(directive)? {
                *config = Some(next);
            }
        }
        C4Statement::Title(_)
        | C4Statement::Element(_)
        | C4Statement::Relationship(_)
        | C4Statement::Boundary(_)
        | C4Statement::Style(_)
        | C4Statement::Layout(_)
        | C4Statement::Comment(_) => {}
    }
    Ok(())
}

fn parse_animation_directive(raw: &str) -> Result<AnimationConfig, AnimationConfigParseError> {
    let mut mode = None;
    let mut speed = AnimationConfig::DEFAULT_SPEED;
    let mut repeat = false;
    let mut easing = AnimationEasing::Linear;

    for field in split_directive_fields(raw) {
        let Some((key, value)) = field.split_once(':') else {
            continue;
        };
        let key = key.trim();
        let value = value.trim();
        match key {
            "animate" => mode = Some(parse_animation_mode(value)?),
            "speed" => speed = parse_animation_speed(value)?,
            "loop" => repeat = parse_animation_loop(value)?,
            "easing" => easing = parse_animation_easing(value)?,
            _ => return Err(AnimationConfigParseError::UnknownField(key.to_owned())),
        }
    }

    AnimationConfig::new(
        mode.ok_or(AnimationConfigParseError::MissingAnimate)?,
        speed,
        repeat,
        easing,
    )
    .map_err(|_| AnimationConfigParseError::InvalidSpeed(speed.to_string()))
}

fn split_directive_fields(raw: &str) -> Vec<&str> {
    let mut fields = Vec::new();
    let mut start = 0usize;
    let mut quote = None;
    for (index, glyph) in raw.char_indices() {
        match (quote, glyph) {
            (Some(active), value) if value == active => quote = None,
            (None, '\'' | '"') => quote = Some(glyph),
            (None, ',') => {
                fields.push(raw[start..index].trim());
                start = index + glyph.len_utf8();
            }
            _ => {}
        }
    }
    fields.push(raw[start..].trim());
    fields
}

fn parse_animation_mode(value: &str) -> Result<AnimationMode, AnimationConfigParseError> {
    match unquote(value) {
        "playback" => Ok(AnimationMode::Playback),
        "trace" => Ok(AnimationMode::Trace),
        "transitions" => Ok(AnimationMode::Transitions),
        "none" => Ok(AnimationMode::None),
        value => Err(AnimationConfigParseError::UnknownMode(value.to_owned())),
    }
}

fn parse_animation_easing(value: &str) -> Result<AnimationEasing, AnimationConfigParseError> {
    match unquote(value) {
        "linear" => Ok(AnimationEasing::Linear),
        "ease" => Ok(AnimationEasing::Ease),
        value => Err(AnimationConfigParseError::UnknownEasing(value.to_owned())),
    }
}

fn parse_animation_speed(value: &str) -> Result<f32, AnimationConfigParseError> {
    let value = unquote(value);
    let Ok(speed) = value.parse::<f32>() else {
        return Err(AnimationConfigParseError::InvalidSpeed(value.to_owned()));
    };
    if !is_valid_animation_speed(speed) {
        return Err(AnimationConfigParseError::InvalidSpeed(value.to_owned()));
    }
    Ok(speed)
}

fn parse_animation_loop(value: &str) -> Result<bool, AnimationConfigParseError> {
    match unquote(value) {
        "true" => Ok(true),
        "false" => Ok(false),
        value => Err(AnimationConfigParseError::InvalidLoop(value.to_owned())),
    }
}

fn unquote(value: &str) -> &str {
    let value = value.trim();
    if value.len() >= 2
        && ((value.starts_with('\'') && value.ends_with('\''))
            || (value.starts_with('"') && value.ends_with('"')))
    {
        &value[1..value.len() - 1]
    } else {
        value
    }
}

fn default_animation_mode(kind: &DiagramKind) -> AnimationMode {
    match kind {
        DiagramKind::Flowchart(_) => AnimationMode::Trace,
        DiagramKind::Sequence(_) => AnimationMode::Playback,
        DiagramKind::State(_) => AnimationMode::Transitions,
        DiagramKind::Class(_) => AnimationMode::Trace,
        DiagramKind::Er(_) => AnimationMode::Trace,
        DiagramKind::Gantt(_) => AnimationMode::Trace,
        DiagramKind::Pie(_) => AnimationMode::Trace,
        DiagramKind::Mindmap(_) => AnimationMode::Trace,
        DiagramKind::Journey(_) => AnimationMode::Trace,
        DiagramKind::GitGraph(_) => AnimationMode::Trace,
        DiagramKind::Timeline(_) => AnimationMode::Trace,
        DiagramKind::Requirement(_) => AnimationMode::None,
        DiagramKind::C4(_) => AnimationMode::None,
    }
}

fn static_timeline(diagram: &Diagram, renderer: StaticFrameRenderer) -> Timeline {
    Timeline::from_frame(
        renderer.render_diagram(diagram),
        default_animation_duration(&diagram.kind),
    )
}

fn default_animation_duration(kind: &DiagramKind) -> Duration {
    match kind {
        DiagramKind::Flowchart(_) => FlowchartTraceAnimator::default_frame_duration(),
        DiagramKind::Sequence(_) => SequencePlaybackAnimator::default_frame_duration(),
        DiagramKind::State(_) => StateTransitionAnimator::default_frame_duration(),
        DiagramKind::Class(_) => ClassRelationshipAnimator::default_frame_duration(),
        DiagramKind::Er(_) => ErRelationshipAnimator::default_frame_duration(),
        DiagramKind::Gantt(_) => GanttSweepAnimator::default_frame_duration(),
        DiagramKind::Pie(_) => PieSliceGrowthAnimator::default_frame_duration(),
        DiagramKind::Mindmap(_) => MindmapExpandAnimator::default_frame_duration(),
        DiagramKind::Journey(_) => JourneyTraceAnimator::default_frame_duration(),
        DiagramKind::GitGraph(_) => GitGraphTraceAnimator::default_frame_duration(),
        DiagramKind::Timeline(_) => TimelineRevealAnimator::default_frame_duration(),
        DiagramKind::Requirement(_) => Duration::from_millis(700),
        DiagramKind::C4(_) => Duration::from_millis(700),
    }
}

fn scaled_duration(duration: Duration, speed: f32) -> Duration {
    Duration::from_secs_f64(duration.as_secs_f64() / f64::from(speed))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyFrame {
    frame: Frame,
    duration: Duration,
}

impl KeyFrame {
    #[must_use]
    pub const fn new(frame: Frame, duration: Duration) -> Self {
        Self { frame, duration }
    }

    #[must_use]
    pub const fn frame(&self) -> &Frame {
        &self.frame
    }

    #[must_use]
    pub const fn duration(&self) -> Duration {
        self.duration
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Timeline {
    keyframes: Vec<KeyFrame>,
    repeat: bool,
}

impl Timeline {
    #[must_use]
    pub const fn new() -> Self {
        Self {
            keyframes: Vec::new(),
            repeat: false,
        }
    }

    #[must_use]
    pub fn from_keyframes(keyframes: Vec<KeyFrame>) -> Self {
        Self {
            keyframes,
            repeat: false,
        }
    }

    #[must_use]
    pub fn from_frame(frame: Frame, duration: Duration) -> Self {
        Self::from_keyframes(vec![KeyFrame::new(frame, duration)])
    }

    #[must_use]
    pub fn with_repeat(mut self, repeat: bool) -> Self {
        self.repeat = repeat;
        self
    }

    pub fn push(&mut self, keyframe: KeyFrame) {
        self.keyframes.push(keyframe);
    }

    #[must_use]
    pub fn keyframes(&self) -> &[KeyFrame] {
        &self.keyframes
    }

    #[must_use]
    pub const fn repeat(&self) -> bool {
        self.repeat
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.keyframes.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.keyframes.is_empty()
    }

    #[must_use]
    pub fn total_duration(&self) -> Duration {
        self.keyframes
            .iter()
            .map(KeyFrame::duration)
            .sum::<Duration>()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FlowchartTraceAnimator {
    frame_duration: Duration,
}

impl Default for FlowchartTraceAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl FlowchartTraceAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(550)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &FlowchartAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(
        self,
        ast: &FlowchartAst,
        renderer: StaticFrameRenderer,
    ) -> Timeline {
        let layout = FlowLayoutEngine::default().layout(ast);
        let mut timeline =
            Timeline::from_frame(renderer.render_flowchart(ast), self.frame_duration);

        for step in flow_trace_steps(&layout) {
            let mut frame = renderer.render_flowchart(ast);
            add_flow_trace_markers(&mut frame, &layout, &step);
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct FlowTraceStep {
    node_index: usize,
    previous_nodes: Vec<usize>,
    active_edges: Vec<usize>,
}

fn flow_trace_steps(layout: &FlowLayout) -> Vec<FlowTraceStep> {
    let mut visited = vec![false; layout.nodes.len()];
    let mut queued = vec![false; layout.nodes.len()];
    let mut steps = Vec::new();

    for root in flow_root_indices(layout) {
        trace_flow_component(layout, root, &mut visited, &mut queued, &mut steps);
    }
    for index in 0..layout.nodes.len() {
        trace_flow_component(layout, index, &mut visited, &mut queued, &mut steps);
    }

    steps
}

fn trace_flow_component(
    layout: &FlowLayout,
    start: usize,
    visited: &mut [bool],
    queued: &mut [bool],
    steps: &mut Vec<FlowTraceStep>,
) {
    if visited[start] {
        return;
    }
    let mut queue = VecDeque::new();
    queue.push_back(start);
    queued[start] = true;

    while let Some(index) = queue.pop_front() {
        if visited[index] {
            continue;
        }
        let previous_nodes = visited
            .iter()
            .enumerate()
            .filter_map(|(index, visited)| (*visited).then_some(index))
            .collect::<Vec<_>>();
        visited[index] = true;
        let active_edges = outgoing_edge_indices(layout, &layout.nodes[index].id);
        for edge_index in &active_edges {
            let edge = &layout.edges[*edge_index];
            let Some(target_index) = flow_node_index(layout, &edge.to) else {
                continue;
            };
            if !visited[target_index] && !queued[target_index] {
                queued[target_index] = true;
                queue.push_back(target_index);
            }
        }
        steps.push(FlowTraceStep {
            node_index: index,
            previous_nodes,
            active_edges,
        });
    }
}

fn flow_root_indices(layout: &FlowLayout) -> Vec<usize> {
    let mut has_incoming = vec![false; layout.nodes.len()];
    for edge in &layout.edges {
        if let Some(index) = flow_node_index(layout, &edge.to) {
            has_incoming[index] = true;
        }
    }
    let roots = has_incoming
        .iter()
        .enumerate()
        .filter_map(|(index, incoming)| (!incoming).then_some(index))
        .collect::<Vec<_>>();
    if roots.is_empty() && !layout.nodes.is_empty() {
        vec![0]
    } else {
        roots
    }
}

fn outgoing_edge_indices(layout: &FlowLayout, node_id: &str) -> Vec<usize> {
    layout
        .edges
        .iter()
        .enumerate()
        .filter_map(|(index, edge)| (edge.from == node_id).then_some(index))
        .collect()
}

fn flow_node_index(layout: &FlowLayout, node_id: &str) -> Option<usize> {
    layout.nodes.iter().position(|node| node.id == node_id)
}

fn add_flow_trace_markers(frame: &mut Frame, layout: &FlowLayout, step: &FlowTraceStep) {
    for node_index in &step.previous_nodes {
        add_flow_node_marker(
            frame,
            &layout.nodes[*node_index],
            KeyFrameMarkerKind::Hold,
            &flow_node_marker_id(&layout.nodes[*node_index].id),
        );
    }

    let current = &layout.nodes[step.node_index];
    add_flow_node_marker(
        frame,
        current,
        KeyFrameMarkerKind::Enter,
        &format!("{}-enter", flow_node_marker_id(&current.id)),
    );
    add_flow_node_marker(
        frame,
        current,
        KeyFrameMarkerKind::Active,
        &flow_node_marker_id(&current.id),
    );

    for edge_index in &step.active_edges {
        add_flow_edge_marker(frame, &layout.edges[*edge_index], *edge_index);
    }
}

fn add_flow_node_marker(
    frame: &mut Frame,
    node: &PositionedFlowNode,
    kind: KeyFrameMarkerKind,
    marker_id: &str,
) {
    let Some(region) = rect_region(
        node.rect.origin.x,
        node.rect.origin.y,
        node.rect.right(),
        node.rect.bottom(),
    ) else {
        return;
    };
    frame.add_marker(KeyFrameMarker {
        id: marker_id.to_owned(),
        kind,
        region,
    });
    mark_region_cells(frame, region, marker_id);
}

fn add_flow_edge_marker(frame: &mut Frame, edge: &PositionedFlowEdge, edge_index: usize) {
    let id = format!("flow-edge-{edge_index}-{}-{}", edge.from, edge.to);
    add_polyline_marker(frame, &edge.points, &id, KeyFrameMarkerKind::Active);
}

fn flow_node_marker_id(node_id: &str) -> String {
    format!("flow-node-{node_id}")
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StateTransitionAnimator {
    frame_duration: Duration,
}

impl Default for StateTransitionAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl StateTransitionAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(650)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &StateAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(self, ast: &StateAst, renderer: StaticFrameRenderer) -> Timeline {
        let layout = StateLayoutEngine::default().layout(ast);
        let mut timeline = Timeline::from_frame(renderer.render_state(ast), self.frame_duration);

        for (index, edge) in layout.graph.edges.iter().enumerate() {
            let mut frame = renderer.render_state(ast);
            add_state_transition_markers(&mut frame, &layout, edge, index);
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

fn add_state_transition_markers(
    frame: &mut Frame,
    layout: &StateLayout,
    edge: &PositionedFlowEdge,
    index: usize,
) {
    if edge.from == "[*]" {
        add_state_node_marker(
            frame,
            &layout.graph,
            &edge.from,
            KeyFrameMarkerKind::Enter,
            &format!("{}-enter", state_node_marker_id(&edge.from)),
        );
    }
    add_state_node_marker(
        frame,
        &layout.graph,
        &edge.from,
        KeyFrameMarkerKind::Exit,
        &state_node_marker_id(&edge.from),
    );
    add_state_transition_edge_marker(frame, edge, index);
    add_state_node_marker(
        frame,
        &layout.graph,
        &edge.to,
        KeyFrameMarkerKind::Enter,
        &format!("{}-enter", state_node_marker_id(&edge.to)),
    );
    add_state_composite_markers(frame, layout, &edge.from, &edge.to);
}

fn add_state_node_marker(
    frame: &mut Frame,
    graph: &FlowLayout,
    node_id: &str,
    kind: KeyFrameMarkerKind,
    marker_id: &str,
) {
    let Some(node) = graph.nodes.iter().find(|node| node.id == node_id) else {
        return;
    };
    add_flow_node_marker(frame, node, kind, marker_id);
}

fn add_state_transition_edge_marker(
    frame: &mut Frame,
    edge: &PositionedFlowEdge,
    edge_index: usize,
) {
    let id = format!("state-transition-{edge_index}-{}-{}", edge.from, edge.to);
    add_polyline_marker(frame, &edge.points, &id, KeyFrameMarkerKind::Active);
}

fn add_state_composite_markers(frame: &mut Frame, layout: &StateLayout, from: &str, to: &str) {
    for composite in &layout.composites {
        if !composite
            .child_ids
            .iter()
            .any(|child| child == from || child == to)
        {
            continue;
        }
        add_state_node_marker(
            frame,
            &layout.graph,
            &composite.id,
            KeyFrameMarkerKind::Hold,
            &format!("state-composite-{}", composite.id),
        );
    }
}

fn state_node_marker_id(node_id: &str) -> String {
    format!("state-node-{node_id}")
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ClassRelationshipAnimator {
    frame_duration: Duration,
}

impl Default for ClassRelationshipAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl ClassRelationshipAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(650)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &ClassAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(self, ast: &ClassAst, renderer: StaticFrameRenderer) -> Timeline {
        let layout = ClassLayoutEngine::default().layout(ast);
        let mut timeline = Timeline::from_frame(renderer.render_class(ast), self.frame_duration);

        for (index, relationship) in layout.relationships.iter().enumerate() {
            let mut frame = renderer.render_class(ast);
            add_class_relationship_markers(&mut frame, &layout, relationship, index);
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

fn add_class_relationship_markers(
    frame: &mut Frame,
    layout: &ClassLayout,
    relationship: &PositionedClassRelationship,
    index: usize,
) {
    add_class_node_marker(
        frame,
        layout,
        &relationship.from,
        KeyFrameMarkerKind::Exit,
        &format!("{}-exit", class_node_marker_id(&relationship.from)),
    );
    add_polyline_marker(
        frame,
        &relationship.points,
        &format!(
            "class-relationship-{index}-{}-{}",
            relationship.from, relationship.to
        ),
        KeyFrameMarkerKind::Active,
    );
    add_class_node_marker(
        frame,
        layout,
        &relationship.to,
        KeyFrameMarkerKind::Enter,
        &format!("{}-enter", class_node_marker_id(&relationship.to)),
    );
}

fn add_class_node_marker(
    frame: &mut Frame,
    layout: &ClassLayout,
    node_id: &str,
    kind: KeyFrameMarkerKind,
    marker_id: &str,
) {
    let Some(node) = layout.nodes.iter().find(|node| node.id == node_id) else {
        return;
    };
    add_positioned_class_node_marker(frame, node, kind, marker_id);
}

fn add_positioned_class_node_marker(
    frame: &mut Frame,
    node: &PositionedClassNode,
    kind: KeyFrameMarkerKind,
    marker_id: &str,
) {
    let Some(region) = rect_region(
        node.rect.origin.x,
        node.rect.origin.y,
        node.rect.right(),
        node.rect.bottom(),
    ) else {
        return;
    };
    frame.add_marker(KeyFrameMarker {
        id: marker_id.to_owned(),
        kind,
        region,
    });
    mark_region_cells(frame, region, marker_id);
}

fn class_node_marker_id(node_id: &str) -> String {
    format!("class-node-{node_id}")
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ErRelationshipAnimator {
    frame_duration: Duration,
}

impl Default for ErRelationshipAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl ErRelationshipAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(650)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &ErAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(self, ast: &ErAst, renderer: StaticFrameRenderer) -> Timeline {
        let layout = ErLayoutEngine::default_values().layout(ast);
        let mut timeline = Timeline::from_frame(renderer.render_er(ast), self.frame_duration);

        for (index, relationship) in layout.relationships.iter().enumerate() {
            let mut frame = renderer.render_er(ast);
            add_er_relationship_markers(&mut frame, &layout, relationship, index);
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

fn add_er_relationship_markers(
    frame: &mut Frame,
    layout: &ClassLayout,
    relationship: &PositionedClassRelationship,
    index: usize,
) {
    add_class_node_marker(
        frame,
        layout,
        &relationship.from,
        KeyFrameMarkerKind::Exit,
        &format!("er-entity-{}-exit", relationship.from),
    );
    add_polyline_marker(
        frame,
        &relationship.points,
        &format!(
            "er-relationship-{index}-{}-{}",
            relationship.from, relationship.to
        ),
        KeyFrameMarkerKind::Active,
    );
    add_class_node_marker(
        frame,
        layout,
        &relationship.to,
        KeyFrameMarkerKind::Enter,
        &format!("er-entity-{}-enter", relationship.to),
    );
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GanttSweepAnimator {
    frame_duration: Duration,
}

impl Default for GanttSweepAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl GanttSweepAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(650)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &GanttAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(self, ast: &GanttAst, renderer: StaticFrameRenderer) -> Timeline {
        let layout = GanttLayoutEngine::default().layout(ast);
        let mut timeline = Timeline::from_frame(renderer.render_gantt(ast), self.frame_duration);
        let mut order = (0..layout.tasks.len()).collect::<Vec<_>>();
        order.sort_by_key(|index| {
            let task = &layout.tasks[*index];
            (task.start, task.end, *index)
        });

        for (step, task_index) in order.iter().enumerate() {
            let mut frame = renderer.render_gantt(ast);
            for previous_index in order.iter().take(step) {
                add_gantt_task_marker(
                    &mut frame,
                    &layout.tasks[*previous_index],
                    *previous_index,
                    KeyFrameMarkerKind::Hold,
                );
            }
            add_gantt_task_marker(
                &mut frame,
                &layout.tasks[*task_index],
                *task_index,
                KeyFrameMarkerKind::Active,
            );
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

fn add_gantt_task_marker(
    frame: &mut Frame,
    task: &PositionedGanttTask,
    index: usize,
    kind: KeyFrameMarkerKind,
) {
    let Some(region) = rect_region(
        task.rect.origin.x,
        task.rect.origin.y,
        task.rect.right(),
        task.rect.bottom(),
    ) else {
        return;
    };
    let id = task.id.as_ref().map_or_else(
        || format!("gantt-task-{index}"),
        |id| format!("gantt-task-{id}"),
    );
    frame.add_marker(KeyFrameMarker {
        id: id.clone(),
        kind,
        region,
    });
    mark_region_cells(frame, region, &id);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PieSliceGrowthAnimator {
    frame_duration: Duration,
}

impl Default for PieSliceGrowthAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl PieSliceGrowthAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(650)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &PieAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(self, ast: &PieAst, renderer: StaticFrameRenderer) -> Timeline {
        let layout = PieLayoutEngine::default().layout(ast);
        let mut timeline =
            Timeline::from_frame(renderer.render_pie_progress(ast, 0), self.frame_duration);

        for index in 0..layout.slices.len() {
            let mut frame = renderer.render_pie_progress(ast, index + 1);
            add_pie_slice_marker(&mut frame, &layout, index, KeyFrameMarkerKind::Active);
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

fn add_pie_slice_marker(
    frame: &mut Frame,
    layout: &PieLayout,
    slice_index: usize,
    kind: KeyFrameMarkerKind,
) {
    let Some(region) = pie_slice_region(layout, slice_index) else {
        return;
    };
    let id = format!("pie-slice-{slice_index}");
    frame.add_marker(KeyFrameMarker {
        id: id.clone(),
        kind,
        region,
    });
    for cell in layout
        .cells
        .iter()
        .filter(|cell| cell.slice_index == slice_index)
    {
        mark_point_cell(frame, cell.point, &id);
    }
}

fn pie_slice_region(layout: &PieLayout, slice_index: usize) -> Option<FrameRegion> {
    let mut cells = layout
        .cells
        .iter()
        .filter(|cell| cell.slice_index == slice_index);
    let first = cells.next()?;
    let mut min_x = first.point.x;
    let mut min_y = first.point.y;
    let mut max_x = first.point.x;
    let mut max_y = first.point.y;
    for cell in cells {
        min_x = min_x.min(cell.point.x);
        min_y = min_y.min(cell.point.y);
        max_x = max_x.max(cell.point.x);
        max_y = max_y.max(cell.point.y);
    }
    region_from_bounds(min_x, min_y, max_x, max_y)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MindmapExpandAnimator {
    frame_duration: Duration,
}

impl Default for MindmapExpandAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl MindmapExpandAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(650)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &MindmapAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(
        self,
        ast: &MindmapAst,
        renderer: StaticFrameRenderer,
    ) -> Timeline {
        let layout = MindmapLayoutEngine::default().layout(ast);
        let max_depth = layout
            .nodes
            .iter()
            .map(|node| node.depth)
            .max()
            .unwrap_or(0);
        let mut timeline = Timeline::from_frame(
            renderer.render_mindmap_progress(ast, 0),
            self.frame_duration,
        );

        for depth in 1..=max_depth {
            let mut frame = renderer.render_mindmap_progress(ast, depth);
            for node in layout.nodes.iter().filter(|node| node.depth == depth) {
                add_mindmap_node_marker(&mut frame, node, KeyFrameMarkerKind::Enter);
            }
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

fn add_mindmap_node_marker(
    frame: &mut Frame,
    node: &PositionedMindmapNode,
    kind: KeyFrameMarkerKind,
) {
    let Some(region) = rect_region(
        node.rect.origin.x,
        node.rect.origin.y,
        node.rect.right(),
        node.rect.bottom(),
    ) else {
        return;
    };
    let id = format!("mindmap-node-{}", node.id);
    frame.add_marker(KeyFrameMarker {
        id: id.clone(),
        kind,
        region,
    });
    mark_region_cells(frame, region, &id);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct JourneyTraceAnimator {
    frame_duration: Duration,
}

impl Default for JourneyTraceAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl JourneyTraceAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(650)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &JourneyAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(
        self,
        ast: &JourneyAst,
        renderer: StaticFrameRenderer,
    ) -> Timeline {
        let layout = JourneyLayoutEngine::default().layout(ast);
        let mut timeline = Timeline::from_frame(
            renderer.render_journey_progress(ast, 0),
            self.frame_duration,
        );

        for (index, task) in layout.tasks.iter().enumerate() {
            let mut frame = renderer.render_journey_progress(ast, index + 1);
            for previous in layout.tasks.iter().take(index) {
                add_journey_task_marker(&mut frame, previous, KeyFrameMarkerKind::Hold);
            }
            add_journey_task_marker(&mut frame, task, KeyFrameMarkerKind::Active);
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

fn add_journey_task_marker(
    frame: &mut Frame,
    task: &PositionedJourneyTask,
    kind: KeyFrameMarkerKind,
) {
    let actor_text_width = task.actors.join(", ").chars().count() as i32;
    let label_right = task.label_origin.x + task.label.chars().count() as i32;
    let score_right = task.score_origin.x + 3;
    let actor_right = task.actors_origin.x + actor_text_width;
    let Some(region) = region_from_bounds(
        task.label_origin.x,
        task.label_origin.y,
        label_right
            .max(task.bar_rect.right())
            .max(score_right)
            .max(actor_right)
            - 1,
        task.label_origin.y,
    ) else {
        return;
    };
    let id = format!("journey-task-{}", task.index);
    frame.add_marker(KeyFrameMarker {
        id: id.clone(),
        kind,
        region,
    });
    mark_region_cells(frame, region, &id);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GitGraphTraceAnimator {
    frame_duration: Duration,
}

impl Default for GitGraphTraceAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl GitGraphTraceAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(650)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &GitGraphAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(
        self,
        ast: &GitGraphAst,
        renderer: StaticFrameRenderer,
    ) -> Timeline {
        let layout = GitGraphLayoutEngine::default().layout(ast);
        let mut timeline = Timeline::from_frame(
            renderer.render_gitgraph_progress(ast, 0),
            self.frame_duration,
        );

        for (index, commit) in layout.commits.iter().enumerate() {
            let mut frame = renderer.render_gitgraph_progress(ast, index + 1);
            for previous in layout.commits.iter().take(index) {
                add_gitgraph_commit_marker(&mut frame, previous, KeyFrameMarkerKind::Hold);
            }
            add_gitgraph_commit_marker(&mut frame, commit, KeyFrameMarkerKind::Active);
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

fn add_gitgraph_commit_marker(
    frame: &mut Frame,
    commit: &PositionedGitGraphCommit,
    kind: KeyFrameMarkerKind,
) {
    let label_right = commit.label_origin.x + commit.id.chars().count() as i32;
    let mut min_x = commit.point.x.min(commit.label_origin.x);
    let mut min_y = commit.point.y.min(commit.label_origin.y);
    let mut max_x = commit.point.x.max(label_right - 1);
    let mut max_y = commit.point.y.max(commit.label_origin.y);
    if let (Some(tag), Some(origin)) = (&commit.tag, commit.tag_origin) {
        min_x = min_x.min(origin.x);
        min_y = min_y.min(origin.y);
        max_x = max_x.max(origin.x + tag.chars().count() as i32 + 1);
        max_y = max_y.max(origin.y);
    }
    let Some(region) = region_from_bounds(min_x, min_y, max_x, max_y) else {
        return;
    };
    let id = format!("gitgraph-commit-{}", commit.index);
    frame.add_marker(KeyFrameMarker {
        id: id.clone(),
        kind,
        region,
    });
    mark_region_cells(frame, region, &id);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TimelineRevealAnimator {
    frame_duration: Duration,
}

impl Default for TimelineRevealAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl TimelineRevealAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(650)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &TimelineAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(
        self,
        ast: &TimelineAst,
        renderer: StaticFrameRenderer,
    ) -> Timeline {
        let layout = TimelineLayoutEngine::default().layout(ast);
        let mut timeline = Timeline::from_frame(
            renderer.render_timeline_progress(ast, 0),
            self.frame_duration,
        );

        for (index, period) in layout.periods.iter().enumerate() {
            let mut frame = renderer.render_timeline_progress(ast, index + 1);
            for previous in layout.periods.iter().take(index) {
                add_timeline_period_marker(&mut frame, previous, KeyFrameMarkerKind::Hold);
            }
            add_timeline_period_marker(&mut frame, period, KeyFrameMarkerKind::Active);
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

fn add_timeline_period_marker(
    frame: &mut Frame,
    period: &PositionedTimelinePeriod,
    kind: KeyFrameMarkerKind,
) {
    let label_right = period.label_origin.x + period.label.chars().count() as i32;
    let mut min_x = period.point.x.min(period.label_origin.x);
    let mut min_y = period.point.y.min(period.label_origin.y);
    let mut max_x = period.point.x.max(label_right - 1);
    let mut max_y = period.point.y.max(period.label_origin.y);
    for (event, origin) in period.events.iter().zip(&period.event_origins) {
        min_x = min_x.min(origin.x);
        min_y = min_y.min(origin.y);
        max_x = max_x.max(origin.x + event.chars().count() as i32 - 1);
        max_y = max_y.max(origin.y);
    }
    let Some(region) = region_from_bounds(min_x, min_y, max_x, max_y) else {
        return;
    };
    let id = format!("timeline-period-{}", period.index);
    frame.add_marker(KeyFrameMarker {
        id: id.clone(),
        kind,
        region,
    });
    mark_region_cells(frame, region, &id);
}

fn add_polyline_marker(frame: &mut Frame, points: &[Point], id: &str, kind: KeyFrameMarkerKind) {
    let Some(region) = polyline_region(points) else {
        return;
    };
    frame.add_marker(KeyFrameMarker {
        id: id.to_owned(),
        kind,
        region,
    });
    mark_polyline_cells(frame, points, id);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SequencePlaybackAnimator {
    frame_duration: Duration,
}

impl Default for SequencePlaybackAnimator {
    fn default() -> Self {
        Self {
            frame_duration: Self::default_frame_duration(),
        }
    }
}

impl SequencePlaybackAnimator {
    #[must_use]
    pub const fn new(frame_duration: Duration) -> Self {
        Self { frame_duration }
    }

    #[must_use]
    pub fn default_frame_duration() -> Duration {
        Duration::from_millis(700)
    }

    #[must_use]
    pub const fn frame_duration(self) -> Duration {
        self.frame_duration
    }

    #[must_use]
    pub fn animate(self, ast: &SequenceAst) -> Timeline {
        self.animate_with_renderer(ast, StaticFrameRenderer::default())
    }

    #[must_use]
    pub fn animate_with_renderer(
        self,
        ast: &SequenceAst,
        renderer: StaticFrameRenderer,
    ) -> Timeline {
        let layout = SequenceLayoutEngine::default().layout(ast);
        let mut timeline = Timeline::new();
        let mut static_frame = renderer.render_sequence(ast);
        add_participant_enter_markers(&mut static_frame, ast, &layout);
        timeline.push(KeyFrame::new(static_frame, self.frame_duration));

        for (index, message) in layout.messages.iter().enumerate() {
            let mut frame = renderer.render_sequence(ast);
            add_active_participant_markers(&mut frame, &layout, message, index);
            add_active_message_marker(&mut frame, message, index);
            timeline.push(KeyFrame::new(frame, self.frame_duration));
        }

        timeline
    }
}

fn add_participant_enter_markers(frame: &mut Frame, ast: &SequenceAst, layout: &SequenceLayout) {
    for declared in &ast.participants {
        let Some(participant) = layout
            .participants
            .iter()
            .find(|participant| participant.id == declared.id.value)
        else {
            continue;
        };
        let Some(region) = participant_header_region(participant) else {
            continue;
        };
        let id = format!("sequence-participant-{}", participant.id);
        frame.add_marker(KeyFrameMarker {
            id: id.clone(),
            kind: KeyFrameMarkerKind::Enter,
            region,
        });
        mark_region_cells(frame, region, &id);
    }
}

fn add_active_participant_markers(
    frame: &mut Frame,
    layout: &SequenceLayout,
    message: &PositionedSequenceMessage,
    message_index: usize,
) {
    let mut ids = Vec::new();
    for id in [message.from.as_str(), message.to.as_str()] {
        if !ids.contains(&id) {
            ids.push(id);
        }
    }

    for id in ids {
        let Some(participant) = layout
            .participants
            .iter()
            .find(|participant| participant.id == id)
        else {
            continue;
        };
        let Some(region) = participant_lane_region(participant, layout) else {
            continue;
        };
        let marker_id = format!("sequence-message-{message_index}-participant-{id}");
        frame.add_marker(KeyFrameMarker {
            id: marker_id.clone(),
            kind: KeyFrameMarkerKind::Active,
            region,
        });
        mark_region_cells(frame, region, &marker_id);
    }
}

fn add_active_message_marker(
    frame: &mut Frame,
    message: &PositionedSequenceMessage,
    message_index: usize,
) {
    let Some(region) = message_region(message) else {
        return;
    };
    let id = format!("sequence-message-{message_index}");
    frame.add_marker(KeyFrameMarker {
        id: id.clone(),
        kind: KeyFrameMarkerKind::Active,
        region,
    });
    mark_message_cells(frame, message, &id);
}

fn participant_header_region(participant: &PositionedSequenceParticipant) -> Option<FrameRegion> {
    rect_region(
        participant.header.origin.x,
        participant.header.origin.y,
        participant.header.right(),
        participant.header.bottom(),
    )
}

fn participant_lane_region(
    participant: &PositionedSequenceParticipant,
    layout: &SequenceLayout,
) -> Option<FrameRegion> {
    region_from_bounds(
        participant.lane_x,
        participant.header.bottom(),
        participant.lane_x,
        layout.size.height,
    )
}

fn message_region(message: &PositionedSequenceMessage) -> Option<FrameRegion> {
    polyline_region(&message.points)
}

fn rect_region(x: i32, y: i32, right: i32, bottom: i32) -> Option<FrameRegion> {
    region_from_bounds(x, y, right.saturating_sub(1), bottom.saturating_sub(1))
}

fn polyline_region(points: &[Point]) -> Option<FrameRegion> {
    let min_x = points.iter().map(|point| point.x).min()?;
    let max_x = points.iter().map(|point| point.x).max()?;
    let min_y = points.iter().map(|point| point.y).min()?;
    let max_y = points.iter().map(|point| point.y).max()?;
    if max_x < 0 || max_y < 0 {
        return None;
    }
    region_from_bounds(min_x.max(0), min_y.max(0), max_x, max_y)
}

fn region_from_bounds(min_x: i32, min_y: i32, max_x: i32, max_y: i32) -> Option<FrameRegion> {
    if max_x < min_x || max_y < min_y {
        return None;
    }
    Some(FrameRegion {
        x: usize::try_from(min_x).ok()?,
        y: usize::try_from(min_y).ok()?,
        width: usize::try_from(max_x - min_x + 1).ok()?,
        height: usize::try_from(max_y - min_y + 1).ok()?,
    })
}

fn mark_region_cells(frame: &mut Frame, region: FrameRegion, marker_id: &str) {
    for y in region.y..region.y.saturating_add(region.height) {
        for x in region.x..region.x.saturating_add(region.width) {
            let _ = frame.mark_cell(x, y, marker_id);
        }
    }
}

fn mark_message_cells(frame: &mut Frame, message: &PositionedSequenceMessage, marker_id: &str) {
    mark_polyline_cells(frame, &message.points, marker_id);
}

fn mark_polyline_cells(frame: &mut Frame, points: &[Point], marker_id: &str) {
    for pair in points.windows(2) {
        mark_segment_cells(frame, pair[0], pair[1], marker_id);
    }
    if points.len() == 1 {
        mark_point_cell(frame, points[0], marker_id);
    }
}

fn mark_segment_cells(frame: &mut Frame, start: Point, end: Point, marker_id: &str) {
    if start.x == end.x {
        for y in start.y.min(end.y)..=start.y.max(end.y) {
            mark_point_cell(frame, Point { x: start.x, y }, marker_id);
        }
    } else if start.y == end.y {
        for x in start.x.min(end.x)..=start.x.max(end.x) {
            mark_point_cell(frame, Point { x, y: start.y }, marker_id);
        }
    } else {
        for x in start.x.min(end.x)..=start.x.max(end.x) {
            mark_point_cell(frame, Point { x, y: start.y }, marker_id);
        }
        for y in start.y.min(end.y)..=start.y.max(end.y) {
            mark_point_cell(frame, Point { x: end.x, y }, marker_id);
        }
    }
}

fn mark_point_cell(frame: &mut Frame, point: Point, marker_id: &str) {
    if let (Ok(x), Ok(y)) = (usize::try_from(point.x), usize::try_from(point.y)) {
        let _ = frame.mark_cell(x, y, marker_id);
    }
}

#[cfg(test)]
mod tests {
    use super::{
        AnimationConfig, AnimationConfigError, AnimationConfigParseError, AnimationDiagramKind,
        AnimationEasing, AnimationMode, AnimationOptions, Animator, FlowchartTraceAnimator,
        KeyFrame, SequencePlaybackAnimator, StateTransitionAnimator, Timeline,
    };
    use crate::ast::{
        ArrowHead, Direction, FlowEdge, FlowEdgeLink, FlowEdgeStroke, FlowNode, FlowShape,
        FlowStatement, FlowchartAst, FlowchartDirective, FlowchartHeader, Label, LabelKind,
        SequenceArrow, SequenceAst, SequenceHeader, SequenceMessage, SequenceParticipant,
        SequenceParticipantKind, SequenceStatement, Span, Spanned, StateAst, StateDirective,
        StateHeader, StateNode, StateNodeKind, StateStatement, StateTransition,
    };
    use crate::frame::{Frame, KeyFrameMarkerKind};
    use crate::parser::Parser;
    use std::time::Duration;

    #[test]
    fn keyframe_stores_frame_and_duration() {
        let frame = Frame::new(2, 1);
        let keyframe = KeyFrame::new(frame.clone(), Duration::from_millis(120));

        assert_eq!(keyframe.frame(), &frame);
        assert_eq!(keyframe.duration(), Duration::from_millis(120));
    }

    #[test]
    fn timeline_preserves_keyframe_order_and_repeat_flag() {
        let mut timeline = Timeline::new().with_repeat(true);
        timeline.push(KeyFrame::new(Frame::new(1, 1), Duration::from_millis(100)));
        timeline.push(KeyFrame::new(Frame::new(2, 1), Duration::from_millis(250)));

        assert_eq!(timeline.len(), 2);
        assert!(timeline.repeat());
        assert_eq!(timeline.keyframes()[1].frame().width(), 2);
        assert_eq!(timeline.total_duration(), Duration::from_millis(350));
    }

    #[test]
    fn timeline_can_wrap_static_frame() {
        let timeline = Timeline::from_frame(Frame::new(3, 2), Duration::from_secs(1));

        assert_eq!(timeline.len(), 1);
        assert!(!timeline.repeat());
        assert_eq!(timeline.total_duration(), Duration::from_secs(1));
    }

    #[test]
    fn animation_config_defaults_to_explicit_none_override() {
        let config = AnimationConfig::default();

        assert_eq!(config.mode, AnimationMode::None);
        assert_eq!(config.speed, 1.0);
        assert!(!config.repeat);
        assert_eq!(config.easing, AnimationEasing::Linear);
    }

    #[test]
    fn animation_config_accepts_schema_fields() {
        let config =
            AnimationConfig::new(AnimationMode::Trace, 1.5, true, AnimationEasing::Ease).unwrap();

        assert_eq!(config.mode, AnimationMode::Trace);
        assert_eq!(config.speed, 1.5);
        assert!(config.repeat);
        assert_eq!(config.easing, AnimationEasing::Ease);
    }

    #[test]
    fn animation_config_rejects_invalid_speed() {
        assert_eq!(
            AnimationConfig::new(AnimationMode::Playback, 0.0, false, AnimationEasing::Linear)
                .unwrap_err(),
            AnimationConfigError::InvalidSpeed,
        );
        assert_eq!(
            AnimationConfig::new(
                AnimationMode::Transitions,
                f32::NAN,
                false,
                AnimationEasing::Linear,
            )
            .unwrap_err(),
            AnimationConfigError::InvalidSpeed,
        );
    }

    #[test]
    fn animation_options_reject_invalid_speed() {
        assert_eq!(
            AnimationOptions::new(Some(0.0), None).unwrap_err(),
            AnimationConfigError::InvalidSpeed,
        );
    }

    #[test]
    fn animation_config_parses_animate_directive() {
        let directive = Parser::parse_mermaid_directive(
            "%%{ animate: 'trace', speed: 2.0, loop: true, easing: 'ease' }%%",
        )
        .unwrap();

        let config = AnimationConfig::from_directive(&directive)
            .unwrap()
            .unwrap();

        assert_eq!(config.mode, AnimationMode::Trace);
        assert_eq!(config.speed, 2.0);
        assert!(config.repeat);
        assert_eq!(config.easing, AnimationEasing::Ease);
    }

    #[test]
    fn animation_config_rejects_unknown_directive_fields() {
        let directive =
            Parser::parse_mermaid_directive("%%{ animate: 'trace', unknown: true }%%").unwrap();

        assert_eq!(
            AnimationConfig::from_directive(&directive).unwrap_err(),
            AnimationConfigParseError::UnknownField("unknown".to_owned()),
        );
    }

    #[test]
    fn animator_uses_default_mode_when_directive_absent() {
        let diagram = Parser::parse_diagram("sequenceDiagram\nAlice->>Bob: hi").unwrap();
        let timeline = Animator::animate_diagram(&diagram).unwrap();

        assert_eq!(timeline.len(), 2);
        assert_eq!(
            timeline.keyframes()[0].duration(),
            Duration::from_millis(700)
        );
        assert!(!timeline.repeat());
    }

    #[test]
    fn animator_feeds_directive_config_into_timeline() {
        let diagram = Parser::parse_diagram(
            "%%{ animate: 'trace', speed: 2.0, loop: true, easing: 'ease' }%%\ngraph TD\nA --> B",
        )
        .unwrap();

        let timeline = Animator::animate_diagram(&diagram).unwrap();

        assert_eq!(timeline.len(), 3);
        assert_eq!(
            timeline.keyframes()[0].duration(),
            Duration::from_millis(275)
        );
        assert!(timeline.repeat());
    }

    #[test]
    fn animator_options_override_directive_speed_and_repeat() {
        let diagram = Parser::parse_diagram(
            "%%{ animate: 'playback', speed: 2.0, loop: false }%%\nsequenceDiagram\nAlice->>Bob: hi",
        )
        .unwrap();
        let options = AnimationOptions::new(Some(4.0), Some(true)).unwrap();

        let timeline = Animator::animate_diagram_with_options(&diagram, options).unwrap();

        assert_eq!(
            timeline.keyframes()[0].duration(),
            Duration::from_millis(175)
        );
        assert!(timeline.repeat());
    }

    #[test]
    fn animator_rejects_mode_for_wrong_diagram_kind() {
        let diagram =
            Parser::parse_diagram("%%{ animate: 'trace' }%%\nsequenceDiagram\nAlice->>Bob: hi")
                .unwrap();

        assert_eq!(
            Animator::animate_diagram(&diagram).unwrap_err(),
            AnimationConfigParseError::UnsupportedMode {
                mode: AnimationMode::Trace,
                diagram: AnimationDiagramKind::Sequence,
            },
        );
    }

    #[test]
    fn animator_explicit_none_returns_static_timeline() {
        let diagram = Parser::parse_diagram("%%{ animate: 'none' }%%\ngraph TD\nA --> B").unwrap();
        let timeline = Animator::animate_diagram(&diagram).unwrap();

        assert_eq!(timeline.len(), 1);
        assert_eq!(
            timeline.keyframes()[0].duration(),
            Duration::from_millis(550)
        );
    }

    #[test]
    fn flowchart_trace_emits_static_frame_plus_bfs_steps() {
        let ast = flowchart(vec![
            FlowStatement::Edge(Box::new(edge("A", "B"))),
            FlowStatement::Edge(Box::new(edge("A", "C"))),
            FlowStatement::Edge(Box::new(edge("B", "D"))),
        ]);

        let timeline = Animator::flowchart_trace(&ast);

        assert_eq!(timeline.len(), 5);
        assert_eq!(timeline.total_duration(), Duration::from_millis(2750));
        assert!(
            timeline
                .keyframes()
                .iter()
                .all(|keyframe| keyframe.duration() == Duration::from_millis(550))
        );

        let first_step = timeline.keyframes()[1].frame();
        assert!(first_step.markers().iter().any(|marker| {
            marker.id == "flow-node-A" && marker.kind == KeyFrameMarkerKind::Active
        }));
        assert!(first_step.markers().iter().any(|marker| {
            marker.id == "flow-node-A-enter" && marker.kind == KeyFrameMarkerKind::Enter
        }));
        assert!(first_step.markers().iter().any(|marker| {
            marker.id == "flow-edge-0-A-B" && marker.kind == KeyFrameMarkerKind::Active
        }));
        assert!(first_step.markers().iter().any(|marker| {
            marker.id == "flow-edge-1-A-C" && marker.kind == KeyFrameMarkerKind::Active
        }));

        let second_step = timeline.keyframes()[2].frame();
        assert!(second_step.markers().iter().any(|marker| {
            marker.id == "flow-node-A" && marker.kind == KeyFrameMarkerKind::Hold
        }));
        assert!(second_step.markers().iter().any(|marker| {
            marker.id == "flow-node-B" && marker.kind == KeyFrameMarkerKind::Active
        }));
    }

    #[test]
    fn flowchart_trace_falls_back_to_source_order_for_cycles() {
        let ast = flowchart(vec![
            FlowStatement::Edge(Box::new(edge("A", "B"))),
            FlowStatement::Edge(Box::new(edge("B", "A"))),
        ]);

        let timeline = FlowchartTraceAnimator::default().animate(&ast);

        assert_eq!(timeline.len(), 3);
        assert!(
            timeline.keyframes()[1]
                .frame()
                .markers()
                .iter()
                .any(|marker| {
                    marker.id == "flow-node-A" && marker.kind == KeyFrameMarkerKind::Active
                })
        );
        assert!(
            timeline.keyframes()[2]
                .frame()
                .markers()
                .iter()
                .any(|marker| {
                    marker.id == "flow-edge-1-B-A" && marker.kind == KeyFrameMarkerKind::Active
                })
        );
    }

    #[test]
    fn flowchart_trace_keeps_empty_flowchart_to_one_frame() {
        let timeline =
            FlowchartTraceAnimator::new(Duration::from_millis(25)).animate(&flowchart(Vec::new()));

        assert_eq!(timeline.len(), 1);
        assert_eq!(timeline.total_duration(), Duration::from_millis(25));
        assert!(timeline.keyframes()[0].frame().markers().is_empty());
    }

    #[test]
    fn state_transitions_emit_static_frame_plus_transition_frames() {
        let ast = state(vec![
            StateStatement::Transition(Box::new(state_transition("[*]", "Idle", "boot"))),
            StateStatement::Transition(Box::new(state_transition("Idle", "Active", "start"))),
        ]);

        let timeline = Animator::state_transitions(&ast);

        assert_eq!(timeline.len(), 3);
        assert_eq!(timeline.total_duration(), Duration::from_millis(1950));
        assert!(
            timeline
                .keyframes()
                .iter()
                .all(|keyframe| keyframe.duration() == Duration::from_millis(650))
        );

        let first_step = timeline.keyframes()[1].frame();
        assert!(first_step.markers().iter().any(|marker| {
            marker.id == "state-node-[*]-enter" && marker.kind == KeyFrameMarkerKind::Enter
        }));
        assert!(first_step.markers().iter().any(|marker| {
            marker.id == "state-node-[*]" && marker.kind == KeyFrameMarkerKind::Exit
        }));
        assert!(first_step.markers().iter().any(|marker| {
            marker.id == "state-transition-0-[*]-Idle" && marker.kind == KeyFrameMarkerKind::Active
        }));
        assert!(first_step.markers().iter().any(|marker| {
            marker.id == "state-node-Idle-enter" && marker.kind == KeyFrameMarkerKind::Enter
        }));

        let second_step = timeline.keyframes()[2].frame();
        assert!(second_step.markers().iter().any(|marker| {
            marker.id == "state-node-Idle" && marker.kind == KeyFrameMarkerKind::Exit
        }));
        assert!(second_step.markers().iter().any(|marker| {
            marker.id == "state-transition-1-Idle-Active"
                && marker.kind == KeyFrameMarkerKind::Active
        }));
    }

    #[test]
    fn state_transitions_mark_composite_parent_hold() {
        let composite = StateNode {
            id: Spanned::new("Composite".to_owned(), Span::new(0, 0)),
            label: None,
            kind: StateNodeKind::Default,
            descriptions: Vec::new(),
            note: None,
            children: vec![
                StateStatement::State(Box::new(state_node("A"))),
                StateStatement::State(Box::new(state_node("B"))),
                StateStatement::Transition(Box::new(state_transition("A", "B", "next"))),
            ],
            span: Span::new(0, 0),
        };
        let ast = state(vec![StateStatement::Composite(Box::new(composite))]);
        let timeline = StateTransitionAnimator::default().animate(&ast);

        assert_eq!(timeline.len(), 2);
        assert!(
            timeline.keyframes()[1]
                .frame()
                .markers()
                .iter()
                .any(|marker| {
                    marker.id == "state-composite-Composite"
                        && marker.kind == KeyFrameMarkerKind::Hold
                })
        );
    }

    #[test]
    fn state_transitions_keep_empty_state_diagram_to_one_frame() {
        let timeline =
            StateTransitionAnimator::new(Duration::from_millis(80)).animate(&state(Vec::new()));

        assert_eq!(timeline.len(), 1);
        assert_eq!(timeline.total_duration(), Duration::from_millis(80));
        assert!(timeline.keyframes()[0].frame().markers().is_empty());
    }

    #[test]
    fn sequence_playback_emits_static_frame_plus_message_frames() {
        let ast = sequence(
            vec![participant("Alice"), participant("Bob")],
            vec![
                message("Alice", "Bob", "hello"),
                message("Bob", "Alice", "reply"),
            ],
        );

        let timeline = Animator::sequence_playback(&ast);

        assert_eq!(timeline.len(), 3);
        assert_eq!(timeline.total_duration(), Duration::from_millis(2100));
        assert!(
            timeline
                .keyframes()
                .iter()
                .all(|keyframe| keyframe.duration() == Duration::from_millis(700))
        );
        assert!(
            timeline.keyframes()[0]
                .frame()
                .markers()
                .iter()
                .any(|marker| marker.id == "sequence-participant-Alice"
                    && marker.kind == KeyFrameMarkerKind::Enter)
        );

        let message_frame = timeline.keyframes()[1].frame();
        let message_marker = message_frame
            .markers()
            .iter()
            .find(|marker| marker.id == "sequence-message-0")
            .unwrap();

        assert_eq!(message_marker.kind, KeyFrameMarkerKind::Active);
        assert!(message_marker.region.width > 1);
        assert_eq!(
            message_frame
                .cell(message_marker.region.x, message_marker.region.y)
                .unwrap()
                .marker
                .as_deref(),
            Some("sequence-message-0"),
        );
        assert!(message_frame.markers().iter().any(|marker| {
            marker.id == "sequence-message-0-participant-Alice"
                && marker.kind == KeyFrameMarkerKind::Active
        }));
    }

    #[test]
    fn sequence_playback_keeps_empty_sequence_to_one_frame() {
        let timeline = SequencePlaybackAnimator::new(Duration::from_millis(50))
            .animate(&sequence(vec![participant("Alice")], Vec::new()));

        assert_eq!(timeline.len(), 1);
        assert_eq!(timeline.total_duration(), Duration::from_millis(50));
        assert_eq!(timeline.keyframes()[0].frame().markers().len(), 1);
    }

    #[test]
    fn sequence_playback_marks_self_message_region() {
        let ast = sequence(
            vec![participant("Alice")],
            vec![message("Alice", "Alice", "self")],
        );
        let timeline = SequencePlaybackAnimator::default().animate(&ast);
        let marker = timeline.keyframes()[1]
            .frame()
            .markers()
            .iter()
            .find(|marker| marker.id == "sequence-message-0")
            .unwrap();

        assert!(marker.region.height > 1);
    }

    fn sequence(
        participants: Vec<SequenceParticipant>,
        statements: Vec<SequenceStatement>,
    ) -> SequenceAst {
        SequenceAst {
            header: SequenceHeader {
                span: Span::new(0, 15),
            },
            statements,
            participants,
            boxes: Vec::new(),
            span: Span::new(0, 0),
        }
    }

    fn participant(id: &str) -> SequenceParticipant {
        SequenceParticipant {
            id: Spanned::new(id.to_owned(), Span::new(0, 0)),
            alias: None,
            kind: SequenceParticipantKind::Participant,
            span: Span::new(0, 0),
        }
    }

    fn message(from: &str, to: &str, text: &str) -> SequenceStatement {
        SequenceStatement::Message(Box::new(SequenceMessage {
            from: Spanned::new(from.to_owned(), Span::new(0, 0)),
            to: Spanned::new(to.to_owned(), Span::new(0, 0)),
            arrow: SequenceArrow::SolidArrow,
            activation: None,
            label: Some(label(text)),
            span: Span::new(0, 0),
        }))
    }

    fn state(statements: Vec<StateStatement>) -> StateAst {
        StateAst {
            header: StateHeader {
                directive: StateDirective::StateDiagramV2,
                span: Span::new(0, 15),
            },
            direction: Some(Spanned::new(Direction::TopDown, Span::new(0, 0))),
            statements,
            states: Vec::new(),
            transitions: Vec::new(),
            classes: Vec::new(),
            span: Span::new(0, 0),
        }
    }

    fn state_transition(from: &str, to: &str, text: &str) -> StateTransition {
        StateTransition {
            from: Spanned::new(from.to_owned(), Span::new(0, 0)),
            to: Spanned::new(to.to_owned(), Span::new(0, 0)),
            label: Some(label(text)),
            span: Span::new(0, 0),
        }
    }

    fn state_node(id: &str) -> StateNode {
        StateNode {
            id: Spanned::new(id.to_owned(), Span::new(0, 0)),
            label: None,
            kind: StateNodeKind::Default,
            descriptions: Vec::new(),
            note: None,
            children: Vec::new(),
            span: Span::new(0, 0),
        }
    }

    fn label(text: &str) -> Label {
        Label {
            text: text.to_owned(),
            kind: LabelKind::Plain,
            span: Span::new(0, 0),
        }
    }

    fn flowchart(statements: Vec<FlowStatement>) -> FlowchartAst {
        FlowchartAst {
            header: FlowchartHeader {
                directive: Spanned::new(FlowchartDirective::Graph, Span::new(0, 5)),
                direction: Spanned::new(Direction::TopDown, Span::new(6, 8)),
                span: Span::new(0, 8),
            },
            statements,
            nodes: Vec::new(),
            edges: Vec::new(),
            subgraphs: Vec::new(),
            classes: Vec::new(),
            span: Span::new(0, 0),
        }
    }

    fn edge(from: &str, to: &str) -> FlowEdge {
        FlowEdge {
            from: flow_node(from),
            to: flow_node(to),
            link: Spanned::new(
                FlowEdgeLink {
                    stroke: FlowEdgeStroke::Normal,
                    arrow_start: ArrowHead::None,
                    arrow_end: ArrowHead::Arrow,
                    min_length: 1,
                },
                Span::new(0, 0),
            ),
            label: None,
            span: Span::new(0, 0),
        }
    }

    fn flow_node(id: &str) -> FlowNode {
        FlowNode {
            id: Spanned::new(id.to_owned(), Span::new(0, 0)),
            label: Some(label(id)),
            shape: Spanned::new(FlowShape::Rectangle, Span::new(0, 0)),
            span: Span::new(0, 0),
        }
    }
}
