use kumeyuri_core::frame::Frame;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct SvgRenderer;

impl SvgRenderer {
    pub fn render_frame(&self, _frame: &Frame) -> String {
        String::new()
    }
}
