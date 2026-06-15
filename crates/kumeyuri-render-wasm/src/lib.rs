use wasm_bindgen::prelude::*;

#[wasm_bindgen]
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct WasmRenderer;

#[wasm_bindgen]
impl WasmRenderer {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Self {
        Self
    }

    pub fn render(&self, source: &str) -> String {
        render(source)
    }
}

#[wasm_bindgen]
pub fn render(source: &str) -> String {
    let _ = source;
    String::new()
}
