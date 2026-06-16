use std::time::Duration;

use kumeyuri_core::{animator::Timeline, frame::Frame};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SvgRenderConfig {
    pub char_width: u16,
    pub line_height: u16,
    pub font_size: u16,
    pub font_family: String,
    pub foreground: String,
    pub background: String,
}

impl Default for SvgRenderConfig {
    fn default() -> Self {
        Self {
            char_width: 8,
            line_height: 16,
            font_size: 14,
            font_family: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace".to_owned(),
            foreground: "#111827".to_owned(),
            background: "#ffffff".to_owned(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SvgRenderer {
    config: SvgRenderConfig,
}

impl Default for SvgRenderer {
    fn default() -> Self {
        Self::new(SvgRenderConfig::default())
    }
}

impl SvgRenderer {
    #[must_use]
    pub const fn new(config: SvgRenderConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub const fn config(&self) -> &SvgRenderConfig {
        &self.config
    }

    #[must_use]
    pub fn render_frame(&self, frame: &Frame) -> String {
        let mut svg = self.open_svg(frame);
        self.push_background(&mut svg, frame);
        self.push_frame_group(&mut svg, frame, "frame-0", 1.0, "");
        svg.push_str("</svg>\n");
        svg
    }

    #[must_use]
    pub fn render_timeline(&self, timeline: &Timeline) -> String {
        let Some(first) = timeline.keyframes().first() else {
            return self.empty_svg();
        };
        let mut svg = self.open_svg(first.frame());
        self.push_background(&mut svg, first.frame());
        let boundaries = animation_boundaries(timeline);
        let total = animation_duration(timeline);
        for (index, keyframe) in timeline.keyframes().iter().enumerate() {
            let animate =
                opacity_animation(index, timeline.len(), timeline.repeat(), &boundaries, total);
            self.push_frame_group(
                &mut svg,
                keyframe.frame(),
                &format!("frame-{index}"),
                if index == 0 { 1.0 } else { 0.0 },
                &animate,
            );
        }
        svg.push_str("</svg>\n");
        svg
    }

    fn empty_svg(&self) -> String {
        let frame = Frame::new(0, 0);
        let mut svg = self.open_svg(&frame);
        svg.push_str("</svg>\n");
        svg
    }

    fn open_svg(&self, frame: &Frame) -> String {
        let width = frame
            .width()
            .saturating_mul(usize::from(self.config.char_width));
        let height = frame
            .height()
            .saturating_mul(usize::from(self.config.line_height));
        format!(
            r#"<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img">
"#
        )
    }

    fn push_background(&self, svg: &mut String, frame: &Frame) {
        let width = frame
            .width()
            .saturating_mul(usize::from(self.config.char_width));
        let height = frame
            .height()
            .saturating_mul(usize::from(self.config.line_height));
        svg.push_str(&format!(
            r#"<rect width="{width}" height="{height}" fill="{}"/>
"#,
            escape_attr(&self.config.background),
        ));
    }

    fn push_frame_group(
        &self,
        svg: &mut String,
        frame: &Frame,
        id: &str,
        opacity: f32,
        animate: &str,
    ) {
        svg.push_str(&format!(
            r#"<g id="{}" opacity="{opacity}">
"#,
            escape_attr(id),
        ));
        svg.push_str(animate);
        for (row, line) in frame.to_lines().into_iter().enumerate() {
            let y = (row + 1).saturating_mul(usize::from(self.config.line_height));
            svg.push_str(&format!(
                r#"<text x="0" y="{y}" xml:space="preserve" font-family="{}" font-size="{}" fill="{}">{}</text>
"#,
                escape_attr(&self.config.font_family),
                self.config.font_size,
                escape_attr(&self.config.foreground),
                escape_text(&line),
            ));
        }
        svg.push_str("</g>\n");
    }
}

fn animation_boundaries(timeline: &Timeline) -> Vec<f64> {
    let count = timeline.len();
    if count == 0 {
        return Vec::new();
    }
    let total = timeline.total_duration().as_secs_f64();
    let mut boundaries = Vec::with_capacity(count + 1);
    boundaries.push(0.0);
    if total == 0.0 {
        for index in 1..count {
            boundaries.push(index as f64 / count as f64);
        }
    } else {
        let mut elapsed = Duration::ZERO;
        for keyframe in timeline.keyframes().iter().take(count.saturating_sub(1)) {
            elapsed += keyframe.duration();
            boundaries.push(elapsed.as_secs_f64() / total);
        }
    }
    boundaries.push(1.0);
    boundaries
}

fn animation_duration(timeline: &Timeline) -> Duration {
    let total = timeline.total_duration();
    if total == Duration::ZERO {
        Duration::from_millis(timeline.len().max(1) as u64)
    } else {
        total
    }
}

fn opacity_animation(
    frame_index: usize,
    frame_count: usize,
    repeat: bool,
    boundaries: &[f64],
    total: Duration,
) -> String {
    let key_times = boundaries
        .iter()
        .map(|time| format_normalized_time(*time))
        .collect::<Vec<_>>()
        .join(";");
    let values = (0..=frame_count)
        .map(|boundary| {
            let active = if boundary == frame_count {
                if repeat {
                    frame_index == 0
                } else {
                    frame_index + 1 == frame_count
                }
            } else {
                boundary == frame_index
            };
            if active { "1" } else { "0" }
        })
        .collect::<Vec<_>>()
        .join(";");
    let repeat_count = if repeat { "indefinite" } else { "1" };
    format!(
        r#"<animate attributeName="opacity" values="{values}" keyTimes="{key_times}" dur="{}ms" repeatCount="{repeat_count}" fill="freeze" calcMode="discrete"/>
"#,
        total.as_millis().max(1),
    )
}

fn format_normalized_time(value: f64) -> String {
    if value == 0.0 {
        "0".to_owned()
    } else if value == 1.0 {
        "1".to_owned()
    } else {
        format!("{value:.6}")
            .trim_end_matches('0')
            .trim_end_matches('.')
            .to_owned()
    }
}

fn escape_text(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn escape_attr(value: &str) -> String {
    escape_text(value).replace('"', "&quot;")
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use kumeyuri_core::{
        animator::{KeyFrame, Timeline},
        frame::Frame,
    };

    use super::SvgRenderer;

    #[test]
    fn renders_static_frame_as_svg_text() {
        let mut frame = Frame::new(5, 1);
        frame.write_text(0, 0, "A<&B", Default::default()).unwrap();

        let svg = SvgRenderer::default().render_frame(&frame);

        assert!(svg.starts_with("<svg "));
        assert!(svg.contains(r#"<g id="frame-0" opacity="1">"#));
        assert!(svg.contains("A&lt;&amp;B"));
        assert!(svg.ends_with("</svg>\n"));
    }

    #[test]
    fn renders_timeline_with_frame_groups_and_smil_animation() {
        let mut first = Frame::new(1, 1);
        first.write_text(0, 0, "A", Default::default()).unwrap();
        let mut second = Frame::new(1, 1);
        second.write_text(0, 0, "B", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![
            KeyFrame::new(first, Duration::from_millis(100)),
            KeyFrame::new(second, Duration::from_millis(300)),
        ])
        .with_repeat(true);

        let svg = SvgRenderer::default().render_timeline(&timeline);

        assert!(svg.contains(r#"<g id="frame-0" opacity="1">"#));
        assert!(svg.contains(r#"<g id="frame-1" opacity="0">"#));
        assert!(svg.contains(r#"attributeName="opacity""#));
        assert!(svg.contains(r#"keyTimes="0;0.25;1""#));
        assert!(svg.contains(r#"dur="400ms""#));
        assert!(svg.contains(r#"repeatCount="indefinite""#));
    }
}
