use std::thread;

use kumeyuri_core::{
    animator::Timeline,
    frame::Frame as CoreFrame,
    text::{TextOutputBackend, TextOutputConfig},
};
use ratatui::{
    Frame, Terminal,
    backend::Backend,
    widgets::{Block, Borders, Paragraph},
};

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct TuiRenderConfig {
    pub trim_trailing_whitespace: bool,
    pub border: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TuiRenderer {
    config: TuiRenderConfig,
    output: TextOutputBackend,
}

impl Default for TuiRenderer {
    fn default() -> Self {
        Self::new(TuiRenderConfig::default())
    }
}

impl TuiRenderer {
    #[must_use]
    pub const fn new(config: TuiRenderConfig) -> Self {
        Self {
            config,
            output: TextOutputBackend::new(TextOutputConfig {
                trim_trailing_whitespace: config.trim_trailing_whitespace,
                final_newline: false,
            }),
        }
    }

    #[must_use]
    pub const fn config(self) -> TuiRenderConfig {
        self.config
    }

    #[must_use]
    pub fn frame_text(self, frame: &CoreFrame) -> String {
        self.output.render_frame(frame)
    }

    pub fn draw<B: Backend>(
        self,
        terminal: &mut Terminal<B>,
        frame: &CoreFrame,
    ) -> Result<(), B::Error> {
        terminal.draw(|area| self.render(area, frame)).map(|_| ())
    }

    pub fn render_timeline<B: Backend>(
        self,
        terminal: &mut Terminal<B>,
        timeline: &Timeline,
    ) -> Result<(), B::Error> {
        loop {
            for keyframe in timeline.keyframes() {
                self.draw(terminal, keyframe.frame())?;
                thread::sleep(keyframe.duration());
            }
            if !timeline.repeat() {
                break;
            }
        }
        Ok(())
    }

    fn render(self, area: &mut Frame<'_>, frame: &CoreFrame) {
        let text = self.frame_text(frame);
        let mut paragraph = Paragraph::new(text);
        if self.config.border {
            paragraph = paragraph.block(Block::default().borders(Borders::ALL));
        }
        area.render_widget(paragraph, area.area());
    }
}

#[cfg(test)]
mod tests {
    use super::{TuiRenderConfig, TuiRenderer};
    use kumeyuri_core::{
        animator::{KeyFrame, Timeline},
        frame::Frame,
    };
    use ratatui::{Terminal, backend::TestBackend};
    use std::time::Duration;

    #[test]
    fn renders_frame_text_without_trimming_by_default() {
        let mut frame = Frame::new(3, 2);
        frame.write_text(0, 0, "A", Default::default()).unwrap();

        assert_eq!(TuiRenderer::default().frame_text(&frame), "A  \n   ");
    }

    #[test]
    fn can_trim_frame_text_for_compact_views() {
        let mut frame = Frame::new(3, 2);
        frame.write_text(0, 0, "A", Default::default()).unwrap();

        let renderer = TuiRenderer::new(TuiRenderConfig {
            trim_trailing_whitespace: true,
            border: false,
        });

        assert_eq!(renderer.frame_text(&frame), "A");
    }

    #[test]
    fn draws_current_frame_to_ratatui_terminal() {
        let mut frame = Frame::new(3, 1);
        frame.write_text(0, 0, "ABC", Default::default()).unwrap();
        let backend = TestBackend::new(5, 2);
        let mut terminal = Terminal::new(backend).unwrap();

        TuiRenderer::default().draw(&mut terminal, &frame).unwrap();

        let buffer = terminal.backend().buffer();
        assert_eq!(buffer[(0, 0)].symbol(), "A");
        assert_eq!(buffer[(1, 0)].symbol(), "B");
        assert_eq!(buffer[(2, 0)].symbol(), "C");
    }

    #[test]
    fn renders_timeline_frames_in_order() {
        let mut first = Frame::new(1, 1);
        first.write_text(0, 0, "A", Default::default()).unwrap();
        let mut second = Frame::new(1, 1);
        second.write_text(0, 0, "B", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![
            KeyFrame::new(first, Duration::ZERO),
            KeyFrame::new(second, Duration::ZERO),
        ]);
        let backend = TestBackend::new(1, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        TuiRenderer::default()
            .render_timeline(&mut terminal, &timeline)
            .unwrap();

        assert_eq!(terminal.backend().buffer()[(0, 0)].symbol(), "B");
    }
}
