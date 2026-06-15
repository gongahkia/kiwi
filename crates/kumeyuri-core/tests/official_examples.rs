use kumeyuri_core::parser::Parser;
use proptest::prelude::*;

const FLOWCHART: &str = include_str!("../../../tests/fuzz/official-mermaid/flowchart.mmd");
const SEQUENCE: &str = include_str!("../../../tests/fuzz/official-mermaid/sequence.mmd");
const STATE: &str = include_str!("../../../tests/fuzz/official-mermaid/state.mmd");

proptest! {
    #[test]
    fn flowchart_official_mermaid_fuzz_corpus_parses(
        leading_blank_lines in 0usize..=2,
        indent_width in 0usize..=4,
        line_ending in prop::sample::select(vec!["\n", "\r\n"]),
        trailing_blank_line in any::<bool>(),
    ) {
        let source = fuzz_whitespace(FLOWCHART, leading_blank_lines, indent_width, line_ending, trailing_blank_line);
        let parsed = parse_flowchart_document(&source);

        prop_assert!(parsed.is_ok(), "{parsed:?}\n{source}");
    }

    #[test]
    fn sequence_official_mermaid_fuzz_corpus_parses(
        leading_blank_lines in 0usize..=2,
        indent_width in 0usize..=4,
        line_ending in prop::sample::select(vec!["\n", "\r\n"]),
        trailing_blank_line in any::<bool>(),
    ) {
        let source = fuzz_whitespace(SEQUENCE, leading_blank_lines, indent_width, line_ending, trailing_blank_line);
        let parsed = parse_sequence_document(&source);

        prop_assert!(parsed.is_ok(), "{parsed:?}\n{source}");
    }

    #[test]
    fn state_official_mermaid_fuzz_corpus_parses(
        leading_blank_lines in 0usize..=2,
        indent_width in 0usize..=4,
        line_ending in prop::sample::select(vec!["\n", "\r\n"]),
        trailing_blank_line in any::<bool>(),
    ) {
        let source = fuzz_whitespace(STATE, leading_blank_lines, indent_width, line_ending, trailing_blank_line);
        let parsed = parse_state_document(&source);

        prop_assert!(parsed.is_ok(), "{parsed:?}\n{source}");
    }
}

fn fuzz_whitespace(
    source: &str,
    leading_blank_lines: usize,
    indent_width: usize,
    line_ending: &str,
    trailing_blank_line: bool,
) -> String {
    let indent = " ".repeat(indent_width);
    let mut lines = Vec::new();
    lines.extend(std::iter::repeat_n(String::new(), leading_blank_lines));
    lines.extend(
        source
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .map(|line| format!("{indent}{line}")),
    );
    if trailing_blank_line {
        lines.push(String::new());
    }
    lines.join(line_ending)
}

fn parse_flowchart_document(source: &str) -> Result<(), String> {
    let lines = non_empty_lines(source);
    let mut index = parse_until_header(&lines, |line| {
        Parser::parse_flowchart_header(line).map(|_| ())
    })?;

    while index < lines.len() {
        let line = lines[index].trim();
        if line.starts_with("subgraph") {
            let (block, next_index) = collect_subgraph(&lines, index)?;
            Parser::parse_flow_subgraph(&block).map_err(|error| format!("{error:?}"))?;
            index = next_index;
            continue;
        }
        parse_flowchart_statement(line)?;
        index += 1;
    }
    Ok(())
}

fn parse_flowchart_statement(line: &str) -> Result<(), String> {
    if Parser::parse_mermaid_directive(line).is_ok()
        || Parser::parse_mermaid_comment(line).is_ok()
        || Parser::parse_flow_class_def(line).is_ok()
        || Parser::parse_flow_class_apply(line).is_ok()
        || Parser::parse_flow_edge(line).is_ok()
        || Parser::parse_flow_node(line).is_ok()
    {
        return Ok(());
    }
    Err(format!("unparsed flowchart statement: {line}"))
}

fn parse_sequence_document(source: &str) -> Result<(), String> {
    let lines = non_empty_lines(source);
    let mut index = parse_until_header(&lines, |line| {
        Parser::parse_sequence_header(line).map(|_| ())
    })?;

    while index < lines.len() {
        Parser::parse_sequence_statement(lines[index].trim())
            .map_err(|error| format!("{error:?}"))?;
        index += 1;
    }
    Ok(())
}

fn parse_state_document(source: &str) -> Result<(), String> {
    let lines = non_empty_lines(source);
    let mut index =
        parse_until_header(&lines, |line| Parser::parse_state_header(line).map(|_| ()))?;

    while index < lines.len() {
        let line = lines[index].trim();
        if line == "}" {
            index += 1;
            continue;
        }
        Parser::parse_state_statement(line).map_err(|error| format!("{error:?}"))?;
        index += 1;
    }
    Ok(())
}

fn parse_until_header<F>(lines: &[&str], parse_header: F) -> Result<usize, String>
where
    F: Fn(&str) -> Result<(), kumeyuri_core::parser::ParseError>,
{
    for (index, line) in lines.iter().enumerate() {
        let trimmed = line.trim();
        if Parser::parse_mermaid_directive(trimmed).is_ok()
            || Parser::parse_mermaid_comment(trimmed).is_ok()
        {
            continue;
        }
        parse_header(trimmed).map_err(|error| format!("{error:?}"))?;
        return Ok(index + 1);
    }
    Err("missing diagram header".to_owned())
}

fn non_empty_lines(source: &str) -> Vec<&str> {
    source
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect()
}

fn collect_subgraph(lines: &[&str], start: usize) -> Result<(String, usize), String> {
    let mut depth = 0usize;
    let mut block = Vec::new();
    for (index, line) in lines.iter().enumerate().skip(start) {
        let trimmed = line.trim();
        if trimmed.starts_with("subgraph") {
            depth += 1;
        }
        if trimmed == "end" {
            depth = depth
                .checked_sub(1)
                .ok_or_else(|| "subgraph depth underflow".to_owned())?;
        }
        block.push(trimmed);
        if depth == 0 {
            return Ok((block.join("\n"), index + 1));
        }
    }
    Err("unterminated subgraph".to_owned())
}
