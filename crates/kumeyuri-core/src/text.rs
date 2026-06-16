use crate::frame::Frame;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TextOutputConfig {
    pub trim_trailing_whitespace: bool,
    pub final_newline: bool,
}

impl Default for TextOutputConfig {
    fn default() -> Self {
        Self {
            trim_trailing_whitespace: true,
            final_newline: false,
        }
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct TextOutputBackend {
    config: TextOutputConfig,
}

impl TextOutputBackend {
    #[must_use]
    pub const fn new(config: TextOutputConfig) -> Self {
        Self { config }
    }

    #[must_use]
    pub const fn exact() -> Self {
        Self {
            config: TextOutputConfig {
                trim_trailing_whitespace: false,
                final_newline: false,
            },
        }
    }

    #[must_use]
    pub const fn config(&self) -> TextOutputConfig {
        self.config
    }

    #[must_use]
    pub fn render_frame(&self, frame: &Frame) -> String {
        let mut lines = frame.to_lines();
        if self.config.trim_trailing_whitespace {
            for line in &mut lines {
                trim_trailing_spaces(line);
            }
        }

        let mut output = lines.join("\n");
        if self.config.final_newline {
            output.push('\n');
        }
        output
    }
}

#[must_use]
pub fn frame_to_text(frame: &Frame) -> String {
    TextOutputBackend::default().render_frame(frame)
}

fn trim_trailing_spaces(line: &mut String) {
    while line.ends_with(' ') {
        line.pop();
    }
}

#[cfg(test)]
mod tests {
    use super::{TextOutputBackend, TextOutputConfig, frame_to_text};
    use crate::frame::Frame;

    #[test]
    fn renders_frame_to_trimmed_text_by_default() {
        let mut frame = Frame::new(4, 2);
        frame.write_text(0, 0, "ab", Default::default()).unwrap();
        frame.write_text(1, 1, "c", Default::default()).unwrap();

        assert_eq!(frame_to_text(&frame), "ab\n c");
        assert_eq!(TextOutputBackend::default().render_frame(&frame), "ab\n c");
    }

    #[test]
    fn exact_backend_preserves_frame_width() {
        let mut frame = Frame::new(3, 1);
        frame.write_text(0, 0, "x", Default::default()).unwrap();

        assert_eq!(TextOutputBackend::exact().render_frame(&frame), "x  ");
    }

    #[test]
    fn can_emit_final_newline() {
        let mut frame = Frame::new(1, 1);
        frame.write_text(0, 0, "x", Default::default()).unwrap();

        assert_eq!(
            TextOutputBackend::new(TextOutputConfig {
                trim_trailing_whitespace: true,
                final_newline: true,
            })
            .render_frame(&frame),
            "x\n",
        );
    }
}
