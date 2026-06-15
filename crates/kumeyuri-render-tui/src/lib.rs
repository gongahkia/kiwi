use kumeyuri_core::frame::Frame;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct TuiRenderer;

impl TuiRenderer {
    pub fn render_frame(&self, _frame: &Frame) {}
}
