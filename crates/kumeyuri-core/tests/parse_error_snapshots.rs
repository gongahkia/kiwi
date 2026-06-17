use std::{fs, path::Path};

use kumeyuri_core::parser::{ParseError, Parser};

const SNAPSHOT_NAMES: [&str; 13] = [
    "flowchart_reserved_end",
    "sequence_missing_target",
    "state_missing_target",
    "class_missing_target",
    "er_missing_target",
    "gantt_missing_metadata",
    "pie_invalid_value",
    "mindmap_empty_icon",
    "journey_invalid_score",
    "gitgraph_invalid_commit_type",
    "timeline_missing_event",
    "requirement_invalid_risk",
    "c4_unclosed_call",
];

#[test]
fn parse_error_snapshots_match() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let update = std::env::var_os("KUMEYURI_UPDATE_PARSE_ERROR_SNAPSHOTS").is_some();

    for name in SNAPSHOT_NAMES {
        let source_path = root
            .join("tests/snapshots/parse-errors/input")
            .join(format!("{name}.mmd"));
        let expected_path = root
            .join("tests/golden/kumeyuri-parse-errors")
            .join(format!("{name}.txt"));
        let source = fs::read_to_string(&source_path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", source_path.display()));
        let error = Parser::parse_diagram(&source).unwrap_err();
        let actual = format_parse_error_snapshot(&source, error);

        if update {
            fs::write(&expected_path, &actual).unwrap_or_else(|error| {
                panic!("failed to write {}: {error}", expected_path.display())
            });
        }
        let expected = fs::read_to_string(&expected_path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", expected_path.display()));

        assert_eq!(actual, expected, "parse error snapshot mismatch for {name}");
    }
}

fn format_parse_error_snapshot(source: &str, error: ParseError) -> String {
    let line = line_at(source, error.span.start);
    let marker = marker_for(line.start, line.end, error.span.start, error.span.end);

    format!(
        "kind: {:?}\nspan: {}..{}\nline: {}\ncolumn: {}\nsource:\n{}\nmarker:\n{}\n{}",
        error.kind,
        error.span.start,
        error.span.end,
        line.number,
        error.span.start.saturating_sub(line.start) + 1,
        source.trim_end(),
        line.text,
        marker,
    )
}

#[derive(Debug, Clone, Copy)]
struct SourceLine<'a> {
    number: usize,
    start: usize,
    end: usize,
    text: &'a str,
}

fn line_at(source: &str, offset: usize) -> SourceLine<'_> {
    let offset = offset.min(source.len());
    let mut number = 1;
    let mut start = 0;
    for (index, byte) in source.bytes().enumerate() {
        if index >= offset {
            break;
        }
        if byte == b'\n' {
            number += 1;
            start = index + 1;
        }
    }
    let end = source[start..]
        .find(['\n', '\r'])
        .map_or(source.len(), |relative| start + relative);

    SourceLine {
        number,
        start,
        end,
        text: &source[start..end],
    }
}

fn marker_for(line_start: usize, line_end: usize, span_start: usize, span_end: usize) -> String {
    let start = span_start.clamp(line_start, line_end);
    let end = span_end
        .max(span_start + 1)
        .clamp(start + 1, line_end.max(start + 1));
    let width = end.saturating_sub(start).max(1);
    format!("{}{}", " ".repeat(start - line_start), "^".repeat(width))
}
