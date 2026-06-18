#![no_main]

use kumeyuri_core::parser::Parser;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(source) = std::str::from_utf8(data) {
        let _ = Parser::parse_diagram(source);
    }
});
