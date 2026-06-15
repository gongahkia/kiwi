use kumeyuri_core::frame::Frame;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct RasterRenderer;

impl RasterRenderer {
    pub fn render_frame(&self, _frame: &Frame) -> Vec<u8> {
        Vec::new()
    }
}
