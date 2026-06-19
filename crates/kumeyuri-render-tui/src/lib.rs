//! ratatui renderer for kumeyuri frames and timelines.

use std::{thread, time::Duration as StdDuration};

use kumeyuri_core::{
    animator::Timeline,
    frame::Frame as CoreFrame,
    text::{TextOutputBackend, TextOutputConfig},
};
use ratatui::{
    Frame, Terminal,
    backend::Backend,
    layout::{Alignment, Rect},
    style::Color,
    widgets::{Block, Borders, Clear, Paragraph},
};
use tachyonfx::{Effect, EffectRenderer, EffectTimer, Interpolation, Motion, fx, fx::Glitch};

/// Configuration for TUI frame rendering.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TuiRenderConfig {
    /// Trim trailing whitespace from rendered frame text.
    pub trim_trailing_whitespace: bool,
    /// Draw a terminal border around the rendered frame.
    pub border: bool,
    /// Transition effect used between timeline frames.
    pub transition: TuiTransitionEffect,
    /// Duration used for one transition tick.
    pub transition_tick: StdDuration,
}

impl Default for TuiRenderConfig {
    fn default() -> Self {
        Self {
            trim_trailing_whitespace: false,
            border: false,
            transition: TuiTransitionEffect::None,
            transition_tick: StdDuration::from_millis(80),
        }
    }
}

/// Visual transition used when drawing timeline frames.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum TuiTransitionEffect {
    /// Draw frames without a transition.
    #[default]
    None,
    /// Fade frame foreground from black.
    Fade,
    /// Slide frame content into the terminal area.
    Slide,
    /// Apply a brief glitch transition.
    Glitch,
}

impl TuiTransitionEffect {
    /// Build the tachyonfx effect for this transition.
    #[must_use]
    pub fn build(self, duration: StdDuration) -> Option<Effect> {
        let timer = effect_timer(duration);
        match self {
            Self::None => None,
            Self::Fade => Some(fx::fade_from_fg(Color::Black, timer)),
            Self::Slide => Some(fx::slide_in(Motion::LeftToRight, 2, 0, Color::Black, timer)),
            Self::Glitch => Some(Effect::new(
                Glitch::builder()
                    .cell_glitch_ratio(0.08)
                    .action_start_delay_ms(0..1)
                    .action_ms(1..effect_duration_ms(duration).max(2))
                    .build(),
            )),
        }
    }
}

/// Renderer that draws kumeyuri frames to a ratatui terminal.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TuiRenderer {
    config: TuiRenderConfig,
    output: TextOutputBackend,
}

/// Debug overlay rendered above a frame.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TuiDebugOverlay {
    /// Smoothed frames-per-second estimate.
    pub fps: f64,
    /// One-based current frame index.
    pub frame_index: usize,
    /// Total frame count.
    pub frame_count: usize,
}

impl Default for TuiRenderer {
    fn default() -> Self {
        Self::new(TuiRenderConfig::default())
    }
}

impl TuiRenderer {
    /// Create a renderer with explicit configuration.
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

    /// Return this renderer's configuration.
    #[must_use]
    pub const fn config(self) -> TuiRenderConfig {
        self.config
    }

    /// Render a frame to plain terminal text.
    #[must_use]
    pub fn frame_text(self, frame: &CoreFrame) -> String {
        self.output.render_frame(frame)
    }

    /// Draw one frame to a terminal.
    pub fn draw<B: Backend>(
        self,
        terminal: &mut Terminal<B>,
        frame: &CoreFrame,
    ) -> Result<(), B::Error> {
        terminal.draw(|area| self.render(area, frame)).map(|_| ())
    }

    /// Draw one frame with an optional debug overlay.
    pub fn draw_with_debug<B: Backend>(
        self,
        terminal: &mut Terminal<B>,
        frame: &CoreFrame,
        overlay: Option<TuiDebugOverlay>,
    ) -> Result<(), B::Error> {
        terminal
            .draw(|area| self.render_with_debug(area, frame, overlay))
            .map(|_| ())
    }

    /// Play a complete timeline in a terminal.
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
        self.render_with_debug(area, frame, None);
    }

    fn render_with_debug(
        self,
        area: &mut Frame<'_>,
        frame: &CoreFrame,
        overlay: Option<TuiDebugOverlay>,
    ) {
        let area_rect = area.area();
        let text = self.frame_text(frame);
        let mut paragraph = Paragraph::new(text);
        if self.config.border {
            paragraph = paragraph.block(Block::default().borders(Borders::ALL));
        }
        area.render_widget(paragraph, area_rect);
        if let Some(mut effect) = self.config.transition.build(self.config.transition_tick) {
            area.render_effect(&mut effect, area_rect, self.config.transition_tick.into());
        }
        if let Some(overlay) = overlay {
            render_debug_overlay(area, area_rect, overlay);
        }
    }
}

fn render_debug_overlay(area: &mut Frame<'_>, area_rect: Rect, overlay: TuiDebugOverlay) {
    let label = format!(
        "fps {:>5.1} | frame {}/{}",
        overlay.fps,
        overlay.frame_index.saturating_add(1),
        overlay.frame_count
    );
    let width = label.len().min(area_rect.width as usize) as u16;
    if width == 0 || area_rect.height == 0 {
        return;
    }
    let rect = Rect {
        x: area_rect.x + area_rect.width.saturating_sub(width),
        y: area_rect.y,
        width,
        height: 1,
    };
    area.render_widget(Clear, rect);
    area.render_widget(Paragraph::new(label).alignment(Alignment::Right), rect);
}

fn effect_timer(duration: StdDuration) -> EffectTimer {
    EffectTimer::from_ms(effect_duration_ms(duration), Interpolation::Linear)
}

fn effect_duration_ms(duration: StdDuration) -> u32 {
    duration.as_millis().clamp(1, u128::from(u32::MAX)) as u32
}

#[cfg(test)]
mod tests {
    use super::{TuiDebugOverlay, TuiRenderConfig, TuiRenderer, TuiTransitionEffect};
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
            ..TuiRenderConfig::default()
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
    fn draws_debug_overlay_when_requested() {
        let mut frame = Frame::new(1, 1);
        frame.write_text(0, 0, "A", Default::default()).unwrap();
        let backend = TestBackend::new(32, 2);
        let mut terminal = Terminal::new(backend).unwrap();

        TuiRenderer::default()
            .draw_with_debug(
                &mut terminal,
                &frame,
                Some(TuiDebugOverlay {
                    fps: 12.5,
                    frame_index: 1,
                    frame_count: 3,
                }),
            )
            .unwrap();

        let content = terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect::<String>();

        assert!(content.contains("fps  12.5"));
        assert!(content.contains("frame 2/3"));
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

    #[test]
    fn builds_supported_transition_effects() {
        let duration = Duration::from_millis(20);

        assert!(TuiTransitionEffect::None.build(duration).is_none());
        assert!(TuiTransitionEffect::Fade.build(duration).is_some());
        assert!(TuiTransitionEffect::Slide.build(duration).is_some());
        assert!(TuiTransitionEffect::Glitch.build(duration).is_some());
    }

    #[test]
    fn applies_transition_effect_during_draw() {
        let mut frame = Frame::new(3, 1);
        frame.write_text(0, 0, "ABC", Default::default()).unwrap();
        let backend = TestBackend::new(5, 2);
        let mut terminal = Terminal::new(backend).unwrap();
        let renderer = TuiRenderer::new(TuiRenderConfig {
            transition: TuiTransitionEffect::Fade,
            transition_tick: Duration::from_millis(20),
            ..TuiRenderConfig::default()
        });

        renderer.draw(&mut terminal, &frame).unwrap();

        assert_eq!(terminal.backend().buffer()[(0, 0)].symbol(), "A");
    }
}
