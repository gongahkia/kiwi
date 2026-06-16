use crate::frame::Frame;
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Animator;

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

#[cfg(test)]
mod tests {
    use super::{KeyFrame, Timeline};
    use crate::frame::Frame;
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
}
