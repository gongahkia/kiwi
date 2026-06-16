use crate::ast::SequenceAst;
use crate::frame::{Frame, FrameRegion, KeyFrameMarker, KeyFrameMarkerKind, StaticFrameRenderer};
use crate::layout::{
    Point, PositionedSequenceMessage, PositionedSequenceParticipant, SequenceLayout,
    SequenceLayoutEngine,
};
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Animator;

impl Animator {
    #[must_use]
    pub fn sequence_playback(ast: &SequenceAst) -> Timeline {
        SequencePlaybackAnimator::default().animate(ast)
    }
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
        let layout = SequenceLayoutEngine::default().layout(ast);
        let renderer = StaticFrameRenderer::default();
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
    region_from_bounds(
        participant.header.origin.x,
        participant.header.origin.y,
        participant.header.right().saturating_sub(1),
        participant.header.bottom().saturating_sub(1),
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
    let min_x = message.points.iter().map(|point| point.x).min()?;
    let max_x = message.points.iter().map(|point| point.x).max()?;
    let min_y = message.points.iter().map(|point| point.y).min()?;
    let max_y = message.points.iter().map(|point| point.y).max()?;
    region_from_bounds(min_x, min_y, max_x, max_y)
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
    for pair in message.points.windows(2) {
        mark_segment_cells(frame, pair[0], pair[1], marker_id);
    }
    if message.points.len() == 1 {
        mark_point_cell(frame, message.points[0], marker_id);
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
    use super::{Animator, KeyFrame, SequencePlaybackAnimator, Timeline};
    use crate::ast::{
        Label, LabelKind, SequenceArrow, SequenceAst, SequenceHeader, SequenceMessage,
        SequenceParticipant, SequenceParticipantKind, SequenceStatement, Span, Spanned,
    };
    use crate::frame::{Frame, KeyFrameMarkerKind};
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
            label: Some(label(text)),
            span: Span::new(0, 0),
        }))
    }

    fn label(text: &str) -> Label {
        Label {
            text: text.to_owned(),
            kind: LabelKind::Plain,
            span: Span::new(0, 0),
        }
    }
}
