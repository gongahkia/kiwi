use std::{
    fs,
    path::{Path, PathBuf},
};

use kumeyuri_core::{
    frame::StaticFrameRenderer,
    parser::Parser,
    text::{TextOutputBackend, TextOutputConfig},
};

const FIXTURE_KINDS: [&str; 13] = [
    "flowchart",
    "sequence",
    "state",
    "class",
    "er",
    "gantt",
    "pie",
    "mindmap",
    "journey",
    "gitgraph",
    "timeline",
    "requirement",
    "c4",
];
const EXPECTED_FIXTURE_COUNT: usize = 89;

#[test]
fn static_fixtures_match_golden_outputs() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let renderer = StaticFrameRenderer::default();
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: true,
        final_newline: false,
    });
    let mut checked = 0usize;

    for kind in FIXTURE_KINDS {
        for source_path in fixture_paths(&root, kind) {
            let stem = source_path
                .file_stem()
                .and_then(|value| value.to_str())
                .expect("fixture has utf-8 stem");
            let expected_path = root
                .join("tests/golden/kumeyuri-static")
                .join(kind)
                .join(format!("{stem}.txt"));
            let source = fs::read_to_string(&source_path).unwrap_or_else(|error| {
                panic!("failed to read {}: {error}", source_path.display())
            });
            let expected = fs::read_to_string(&expected_path).unwrap_or_else(|error| {
                panic!("failed to read {}: {error}", expected_path.display())
            });
            let diagram = Parser::parse_diagram(&source).unwrap_or_else(|error| {
                panic!(
                    "failed to parse {}: {:?} at {}..{}",
                    source_path.display(),
                    error.kind,
                    error.span.start,
                    error.span.end,
                )
            });
            let actual = text.render_frame(&renderer.render_diagram(&diagram));

            assert_eq!(actual, expected, "visual diff mismatch for {kind}/{stem}");
            checked += 1;
        }
    }

    assert_eq!(checked, EXPECTED_FIXTURE_COUNT);
}

fn fixture_paths(root: &Path, kind: &str) -> Vec<PathBuf> {
    let mut paths = fs::read_dir(root.join("tests/snapshots").join(kind).join("input"))
        .unwrap_or_else(|error| panic!("failed to read {kind} fixture dir: {error}"))
        .map(|entry| entry.expect("fixture dir entry is readable").path())
        .filter(|path| path.extension().and_then(|value| value.to_str()) == Some("mmd"))
        .collect::<Vec<_>>();
    paths.sort();
    paths
}
