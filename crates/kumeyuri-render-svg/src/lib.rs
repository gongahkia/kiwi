use std::time::Duration;

use kumeyuri_core::{animator::Timeline, frame::Frame};

const MAX_PROGRESS_DOTS: usize = 32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SvgRenderConfig {
    pub char_width: u16,
    pub line_height: u16,
    pub padding: u16,
    pub font_size: u16,
    pub font_family: String,
    pub foreground: String,
    pub background: String,
    pub dark_foreground: Option<String>,
    pub dark_background: Option<String>,
    pub animation: SvgAnimationMode,
    pub title: String,
    pub description: String,
}

impl Default for SvgRenderConfig {
    fn default() -> Self {
        Self {
            char_width: 8,
            line_height: 16,
            padding: 0,
            font_size: 14,
            font_family: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace".to_owned(),
            foreground: "#111827".to_owned(),
            background: "#ffffff".to_owned(),
            dark_foreground: None,
            dark_background: None,
            animation: SvgAnimationMode::Smil,
            title: "kumeyuri diagram".to_owned(),
            description: "text-rendered Mermaid diagram".to_owned(),
        }
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum SvgAnimationMode {
    #[default]
    Smil,
    CssKeyframes,
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
        let (width, height) = self.svg_dimensions(frame, 0, 0);
        let mut svg = open_svg(width, height);
        self.push_accessibility(&mut svg, &frame_fallback(frame));
        self.push_color_scheme_style(&mut svg);
        self.push_background(&mut svg, width, height);
        self.push_frame_group(&mut svg, frame, "frame-0", 1.0, "");
        svg.push_str("</svg>\n");
        svg
    }

    #[must_use]
    pub fn render_timeline(&self, timeline: &Timeline) -> String {
        let Some(first) = timeline.keyframes().first() else {
            return self.empty_svg();
        };
        let progress_dot_count = progress_dot_count(timeline.len());
        let progress_row_count = if progress_dot_count > 0 { 1 } else { 0 };
        let (width, height) =
            self.svg_dimensions(first.frame(), progress_row_count, progress_dot_count);
        let mut svg = open_svg(width, height);
        self.push_accessibility(&mut svg, &timeline_fallback(timeline));
        self.push_color_scheme_style(&mut svg);
        let boundaries = animation_boundaries(timeline);
        let total = animation_duration(timeline);
        if self.config.animation == SvgAnimationMode::CssKeyframes {
            self.push_css_keyframes(&mut svg, timeline, &boundaries, total);
        }
        self.push_reduced_motion_style(&mut svg, timeline.len());
        self.push_background(&mut svg, width, height);
        for (index, keyframe) in timeline.keyframes().iter().enumerate() {
            let animate = match self.config.animation {
                SvgAnimationMode::Smil => {
                    opacity_animation(index, timeline.len(), timeline.repeat(), &boundaries, total)
                }
                SvgAnimationMode::CssKeyframes => String::new(),
            };
            self.push_frame_group(
                &mut svg,
                keyframe.frame(),
                &format!("frame-{index}"),
                if index == 0 { 1.0 } else { 0.0 },
                &animate,
            );
        }
        self.push_progress_dots(&mut svg, first.frame(), progress_dot_count, width);
        svg.push_str("</svg>\n");
        svg
    }

    fn empty_svg(&self) -> String {
        let frame = Frame::new(0, 0);
        let (width, height) = self.svg_dimensions(&frame, 0, 0);
        let mut svg = open_svg(width, height);
        svg.push_str("</svg>\n");
        svg
    }

    fn svg_dimensions(
        &self,
        frame: &Frame,
        extra_rows: usize,
        min_content_columns: usize,
    ) -> (usize, usize) {
        let width = frame
            .width()
            .max(min_content_columns)
            .saturating_mul(usize::from(self.config.char_width))
            .saturating_add(usize::from(self.config.padding).saturating_mul(2));
        let height = frame
            .height()
            .saturating_add(extra_rows)
            .saturating_mul(usize::from(self.config.line_height))
            .saturating_add(usize::from(self.config.padding).saturating_mul(2));
        (width, height)
    }

    fn push_accessibility(&self, svg: &mut String, fallback: &str) {
        svg.push_str(&format!(
            r#"<title id="kumeyuri-title">{}</title>
<desc id="kumeyuri-desc">{}</desc>
<metadata id="kumeyuri-text-fallback" data-format="text/plain">{}</metadata>
"#,
            escape_text(&self.config.title),
            escape_text(&self.config.description),
            escape_text(fallback),
        ));
    }

    fn push_background(&self, svg: &mut String, width: usize, height: usize) {
        svg.push_str(&format!(
            r#"<rect width="{width}" height="{height}" fill="{}"/>
"#,
            escape_attr(&self.config.background),
        ));
    }

    fn push_color_scheme_style(&self, svg: &mut String) {
        let (Some(dark_foreground), Some(dark_background)) =
            (&self.config.dark_foreground, &self.config.dark_background)
        else {
            return;
        };
        svg.push_str("<style>\n");
        svg.push_str(&format!(
            "rect {{ fill: {}; }}\ntext {{ fill: {}; }}\n",
            escape_text(&self.config.background),
            escape_text(&self.config.foreground),
        ));
        svg.push_str("@media (prefers-color-scheme: dark) {\n");
        svg.push_str(&format!(
            "  rect {{ fill: {}; }}\n  text {{ fill: {}; }}\n",
            escape_text(dark_background),
            escape_text(dark_foreground),
        ));
        svg.push_str("}\n</style>\n");
    }

    fn push_css_keyframes(
        &self,
        svg: &mut String,
        timeline: &Timeline,
        boundaries: &[f64],
        total: Duration,
    ) {
        svg.push_str("<style>\n");
        for index in 0..timeline.len() {
            svg.push_str(&format!(
                "#frame-{index} {{ animation: kumeyuri-frame-{index} "
            ));
            svg.push_str(&format!(
                "{}ms step-end {} forwards; }}\n",
                total.as_millis().max(1),
                if timeline.repeat() { "infinite" } else { "1" },
            ));
            svg.push_str(&format!("@keyframes kumeyuri-frame-{index} {{\n"));
            for (boundary, time) in boundaries.iter().enumerate() {
                svg.push_str(&format!(
                    "  {}% {{ opacity: {}; }}\n",
                    format_percent(*time),
                    opacity_value(index, timeline.len(), timeline.repeat(), boundary),
                ));
            }
            svg.push_str("}\n");
        }
        svg.push_str("</style>\n");
    }

    fn push_reduced_motion_style(&self, svg: &mut String, frame_count: usize) {
        if frame_count < 2 {
            return;
        }
        svg.push_str("<style>\n");
        svg.push_str("@media (prefers-reduced-motion: reduce) {\n");
        svg.push_str(
            "  g[id^=\"frame-\"] { animation: none !important; opacity: 0 !important; }\n",
        );
        svg.push_str("  #frame-0 { opacity: 1 !important; }\n");
        svg.push_str("  #kumeyuri-progress-dots { opacity: 1 !important; }\n");
        svg.push_str("}\n</style>\n");
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
            let x = usize::from(self.config.padding);
            let y = usize::from(self.config.padding)
                .saturating_add((row + 1).saturating_mul(usize::from(self.config.line_height)));
            svg.push_str(&format!(
                r#"<text x="{x}" y="{y}" xml:space="preserve" font-family="{}" font-size="{}" fill="{}">{}</text>
"#,
                escape_attr(&self.config.font_family),
                self.config.font_size,
                escape_attr(&self.config.foreground),
                escape_text(&line),
            ));
        }
        svg.push_str("</g>\n");
    }

    fn push_progress_dots(
        &self,
        svg: &mut String,
        frame: &Frame,
        dot_count: usize,
        svg_width: usize,
    ) {
        if dot_count == 0 {
            return;
        }
        let dots = ".".repeat(dot_count);
        let padding = usize::from(self.config.padding);
        let char_width = usize::from(self.config.char_width);
        let line_height = usize::from(self.config.line_height);
        let x = svg_width
            .saturating_sub(padding)
            .saturating_sub(dot_count.saturating_mul(char_width));
        let y = padding.saturating_add((frame.height() + 1).saturating_mul(line_height));
        svg.push_str(&format!(
            r#"<text id="kumeyuri-progress-dots" opacity="0" x="{x}" y="{y}" xml:space="preserve" font-family="{}" font-size="{}" fill="{}">{}</text>
"#,
            escape_attr(&self.config.font_family),
            self.config.font_size,
            escape_attr(&self.config.foreground),
            escape_text(&dots),
        ));
    }
}

fn open_svg(width: usize, height: usize) -> String {
    format!(
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="kumeyuri-title kumeyuri-desc">
"#
    )
}

fn progress_dot_count(frame_count: usize) -> usize {
    if frame_count < 2 {
        0
    } else {
        frame_count.min(MAX_PROGRESS_DOTS)
    }
}

fn frame_fallback(frame: &Frame) -> String {
    frame.to_lines().join("\n")
}

fn timeline_fallback(timeline: &Timeline) -> String {
    let mut fallback = String::new();
    for (index, keyframe) in timeline.keyframes().iter().enumerate() {
        if index > 0 {
            fallback.push_str("\n\n");
        }
        fallback.push_str(&format!("frame {index}\n"));
        fallback.push_str(&frame_fallback(keyframe.frame()));
    }
    fallback
}

fn opacity_value(
    frame_index: usize,
    frame_count: usize,
    repeat: bool,
    boundary: usize,
) -> &'static str {
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
        .map(|boundary| opacity_value(frame_index, frame_count, repeat, boundary))
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

fn format_percent(value: f64) -> String {
    if value == 0.0 {
        "0".to_owned()
    } else if value == 1.0 {
        "100".to_owned()
    } else {
        format!("{:.4}", value * 100.0)
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

    use super::{SvgAnimationMode, SvgRenderConfig, SvgRenderer};

    #[test]
    fn renders_static_frame_as_svg_text() {
        let mut frame = Frame::new(5, 1);
        frame.write_text(0, 0, "A<&B", Default::default()).unwrap();

        let svg = SvgRenderer::default().render_frame(&frame);

        assert!(svg.starts_with("<svg "));
        assert!(svg.contains(r#"<title id="kumeyuri-title">kumeyuri diagram</title>"#));
        assert!(svg.contains(r#"<desc id="kumeyuri-desc">text-rendered Mermaid diagram</desc>"#));
        assert!(svg.contains(
            r#"<metadata id="kumeyuri-text-fallback" data-format="text/plain">A&lt;&amp;B </metadata>"#
        ));
        assert!(svg.contains(r#"<g id="frame-0" opacity="1">"#));
        assert!(svg.contains("A&lt;&amp;B"));
        assert!(!svg.contains("prefers-reduced-motion"));
        assert!(!svg.contains("kumeyuri-progress-dots"));
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
        assert!(svg.contains("@media (prefers-reduced-motion: reduce)"));
        assert!(
            svg.contains(
                r#"g[id^="frame-"] { animation: none !important; opacity: 0 !important; }"#
            )
        );
        assert!(svg.contains(r#"#frame-0 { opacity: 1 !important; }"#));
        assert!(svg.contains(r#"#kumeyuri-progress-dots { opacity: 1 !important; }"#));
        assert!(svg.contains(
            r#"<text id="kumeyuri-progress-dots" opacity="0" x="0" y="32" xml:space="preserve""#
        ));
        assert!(svg.contains(">..</text>"));
        assert!(svg.contains("frame 0\nA\n\nframe 1\nB"));
    }

    #[test]
    fn renders_timeline_with_css_keyframe_fallback() {
        let mut first = Frame::new(1, 1);
        first.write_text(0, 0, "A", Default::default()).unwrap();
        let mut second = Frame::new(1, 1);
        second.write_text(0, 0, "B", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![
            KeyFrame::new(first, Duration::from_millis(100)),
            KeyFrame::new(second, Duration::from_millis(300)),
        ]);
        let renderer = SvgRenderer::new(SvgRenderConfig {
            animation: SvgAnimationMode::CssKeyframes,
            ..SvgRenderConfig::default()
        });

        let svg = renderer.render_timeline(&timeline);

        assert!(svg.contains("<style>"));
        assert!(svg.contains("@keyframes kumeyuri-frame-0"));
        assert!(
            svg.contains("#frame-0 { animation: kumeyuri-frame-0 400ms step-end 1 forwards; }")
        );
        assert!(svg.contains("25% { opacity: 0; }"));
        assert!(svg.contains("@media (prefers-reduced-motion: reduce)"));
        assert!(svg.contains(r#"<text id="kumeyuri-progress-dots" opacity="0""#));
        assert!(!svg.contains(r#"<animate attributeName="opacity""#));
    }

    #[test]
    fn renders_prefers_color_scheme_style_when_dark_colors_are_set() {
        let mut frame = Frame::new(1, 1);
        frame.write_text(0, 0, "A", Default::default()).unwrap();
        let renderer = SvgRenderer::new(SvgRenderConfig {
            foreground: "#111111".to_owned(),
            background: "#ffffff".to_owned(),
            dark_foreground: Some("#eeeeee".to_owned()),
            dark_background: Some("#000000".to_owned()),
            ..SvgRenderConfig::default()
        });

        let svg = renderer.render_frame(&frame);

        assert!(svg.contains("@media (prefers-color-scheme: dark)"));
        assert!(svg.contains("rect { fill: #ffffff; }"));
        assert!(svg.contains("text { fill: #111111; }"));
        assert!(svg.contains("rect { fill: #000000; }"));
        assert!(svg.contains("text { fill: #eeeeee; }"));
    }

    #[test]
    fn escapes_user_content_without_forbidden_svg_markup() {
        let mut frame = Frame::new(60, 1);
        frame
            .write_text(
                0,
                0,
                r#"<foreignObject><script href="https://evil.test">"#,
                Default::default(),
            )
            .unwrap();
        let renderer = SvgRenderer::new(SvgRenderConfig {
            title: r#"<script>title</script>"#.to_owned(),
            description: r#"<foreignObject href="https://evil.test">"#.to_owned(),
            ..SvgRenderConfig::default()
        });

        let svg = renderer.render_frame(&frame);

        assert!(svg.contains("&lt;script&gt;title&lt;/script&gt;"));
        assert!(svg.contains("&lt;foreignObject href=\"https://evil.test\"&gt;"));
        assert_no_forbidden_svg_tags(&svg);
    }

    fn assert_no_forbidden_svg_tags(svg: &str) {
        for tag in raw_svg_tags(svg) {
            let lower = tag.to_ascii_lowercase();
            assert!(
                !lower.starts_with("<foreignobject") && !lower.starts_with("</foreignobject"),
                "forbidden foreignObject tag emitted: {tag}"
            );
            assert!(
                !lower.starts_with("<script") && !lower.starts_with("</script"),
                "forbidden script tag emitted: {tag}"
            );
            assert!(
                !lower.contains(" href=") && !lower.contains(" xlink:href="),
                "forbidden external link attribute emitted: {tag}"
            );
        }
    }

    fn raw_svg_tags(svg: &str) -> Vec<&str> {
        let mut tags = Vec::new();
        let mut cursor = 0;
        while let Some(start_offset) = svg[cursor..].find('<') {
            let start = cursor + start_offset;
            let Some(end_offset) = svg[start..].find('>') else {
                break;
            };
            let end = start + end_offset + 1;
            tags.push(&svg[start..end]);
            cursor = end;
        }
        tags
    }
}
