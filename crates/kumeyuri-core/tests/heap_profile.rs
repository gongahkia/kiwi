#![cfg(feature = "dhat-heap")]

use std::{fs, path::Path};

use kumeyuri_core::{
    frame::StaticFrameRenderer,
    parser::Parser,
    text::{TextOutputBackend, TextOutputConfig},
};

#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

const FIXTURES: [(&str, &str); 28] = [
    (
        "flowchart",
        include_str!("../../../tests/fuzz/official-mermaid/flowchart.mmd"),
    ),
    (
        "sequence",
        include_str!("../../../tests/fuzz/official-mermaid/sequence.mmd"),
    ),
    (
        "state",
        include_str!("../../../tests/fuzz/official-mermaid/state.mmd"),
    ),
    (
        "class",
        include_str!("../../../tests/fuzz/official-mermaid/class.mmd"),
    ),
    (
        "er",
        include_str!("../../../tests/fuzz/official-mermaid/er.mmd"),
    ),
    (
        "gantt",
        include_str!("../../../tests/fuzz/official-mermaid/gantt.mmd"),
    ),
    (
        "pie",
        include_str!("../../../tests/fuzz/official-mermaid/pie.mmd"),
    ),
    (
        "quadrant",
        include_str!("../../../tests/fuzz/official-mermaid/quadrant.mmd"),
    ),
    (
        "zenuml",
        include_str!("../../../tests/fuzz/official-mermaid/zenuml.mmd"),
    ),
    (
        "sankey",
        include_str!("../../../tests/fuzz/official-mermaid/sankey.mmd"),
    ),
    (
        "xychart",
        include_str!("../../../tests/fuzz/official-mermaid/xychart.mmd"),
    ),
    (
        "block",
        include_str!("../../../tests/fuzz/official-mermaid/block.mmd"),
    ),
    (
        "packet",
        include_str!("../../../tests/fuzz/official-mermaid/packet.mmd"),
    ),
    (
        "kanban",
        include_str!("../../../tests/fuzz/official-mermaid/kanban.mmd"),
    ),
    (
        "architecture",
        include_str!("../../../tests/fuzz/official-mermaid/architecture.mmd"),
    ),
    (
        "radar",
        include_str!("../../../tests/fuzz/official-mermaid/radar.mmd"),
    ),
    (
        "eventmodeling",
        include_str!("../../../tests/fuzz/official-mermaid/eventmodeling.mmd"),
    ),
    (
        "treemap",
        include_str!("../../../tests/fuzz/official-mermaid/treemap.mmd"),
    ),
    (
        "venn",
        include_str!("../../../tests/fuzz/official-mermaid/venn.mmd"),
    ),
    (
        "ishikawa",
        include_str!("../../../tests/fuzz/official-mermaid/ishikawa.mmd"),
    ),
    (
        "wardley",
        include_str!("../../../tests/fuzz/official-mermaid/wardley.mmd"),
    ),
    (
        "tree_view",
        include_str!("../../../tests/fuzz/official-mermaid/tree_view.mmd"),
    ),
    (
        "mindmap",
        include_str!("../../../tests/fuzz/official-mermaid/mindmap.mmd"),
    ),
    (
        "journey",
        include_str!("../../../tests/fuzz/official-mermaid/journey.mmd"),
    ),
    (
        "gitgraph",
        include_str!("../../../tests/fuzz/official-mermaid/gitgraph.mmd"),
    ),
    (
        "timeline",
        include_str!("../../../tests/fuzz/official-mermaid/timeline.mmd"),
    ),
    (
        "requirement",
        include_str!("../../../tests/fuzz/official-mermaid/requirement.mmd"),
    ),
    (
        "c4",
        include_str!("../../../tests/fuzz/official-mermaid/c4.mmd"),
    ),
];

#[test]
fn heap_profile_official_render_corpus() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let output = root.join("target/dhat/kumeyuri-core-heap.json");
    fs::create_dir_all(output.parent().expect("profile output has parent"))
        .expect("creates dhat output directory");

    let _profiler = dhat::Profiler::builder().file_name(output).build();
    let renderer = StaticFrameRenderer::default();
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: true,
        final_newline: false,
    });

    for (name, source) in FIXTURES {
        let diagram =
            Parser::parse_diagram(source).unwrap_or_else(|error| panic!("{name}: {error:?}"));
        let frame = renderer.render_diagram(&diagram);
        assert!(!text.render_frame(&frame).is_empty(), "{name} renders text");
    }

    let stats = dhat::HeapStats::get();
    assert!(stats.total_blocks > 0);
    assert!(stats.max_bytes > 0);
}
