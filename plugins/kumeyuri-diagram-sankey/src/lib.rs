pub const PLUGIN_NAME: &str = "kumeyuri-diagram-sankey";
pub const ABI_VERSION: &str = "1.0";
pub const DIAGRAM_TYPE: &str = "sankey";
pub const DEFAULT_ANIMATION: &str = "none";
pub const ROOTS: &[&str] = &["sankey", "sankey-beta"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SankeyDocument {
    pub header: String,
    pub links: Vec<SankeyLink>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SankeyLink {
    pub source: String,
    pub target: String,
    pub value_units: u64,
    pub value_text: String,
}

pub fn parse_reference_sankey(source: &str) -> Result<SankeyDocument, String> {
    let mut lines = source.lines().enumerate();
    let Some((_, header_line)) = lines.find(|(_, line)| !line.trim().is_empty()) else {
        return Err("missing sankey header".to_owned());
    };
    let header = header_line.trim();
    if !ROOTS.contains(&header) {
        return Err(format!("expected sankey header, got {header}"));
    }

    let mut links = Vec::new();
    for (index, line) in lines {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with("%%") {
            continue;
        }
        let fields =
            parse_csv_fields(line).map_err(|error| format!("line {}: {error}", index + 1))?;
        if fields.len() != 3 {
            return Err(format!("line {}: expected 3 CSV fields", index + 1));
        }
        let source = fields[0].trim();
        let target = fields[1].trim();
        if source.is_empty() || target.is_empty() {
            return Err(format!("line {}: expected source and target", index + 1));
        }
        let value_text = fields[2].trim();
        let Some(value_units) = parse_value_units(value_text) else {
            return Err(format!(
                "line {}: expected positive sankey value",
                index + 1
            ));
        };
        links.push(SankeyLink {
            source: source.to_owned(),
            target: target.to_owned(),
            value_units,
            value_text: value_text.to_owned(),
        });
    }
    if links.is_empty() {
        return Err("expected at least one sankey link".to_owned());
    }
    Ok(SankeyDocument {
        header: header.to_owned(),
        links,
    })
}

#[must_use]
pub fn lower_reference_frames(document: &SankeyDocument) -> String {
    let mut output = String::from("{\"type\":\"sankey\",\"animation\":\"none\",\"links\":[");
    for (index, link) in document.links.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push_str(&format!(
            "{{\"source\":\"{}\",\"target\":\"{}\",\"valueUnits\":{},\"value\":\"{}\"}}",
            escape_json(&link.source),
            escape_json(&link.target),
            link.value_units,
            escape_json(&link.value_text)
        ));
    }
    output.push_str("]}");
    output
}

fn parse_csv_fields(line: &str) -> Result<Vec<String>, String> {
    let mut fields = Vec::new();
    let mut field = String::new();
    let mut quoted = false;
    let mut saw_quote = false;
    let mut chars = line.chars().peekable();

    while let Some(character) = chars.next() {
        match character {
            '"' if quoted => {
                if matches!(chars.peek(), Some('"')) {
                    field.push('"');
                    chars.next();
                } else {
                    quoted = false;
                }
            }
            '"' if !quoted && field.trim().is_empty() && !saw_quote => {
                field.clear();
                quoted = true;
                saw_quote = true;
            }
            ',' if !quoted => {
                fields.push(field.trim().to_owned());
                field.clear();
                saw_quote = false;
            }
            character => field.push(character),
        }
    }
    if quoted {
        return Err("unterminated quoted field".to_owned());
    }
    fields.push(field.trim().to_owned());
    Ok(fields)
}

fn parse_value_units(value: &str) -> Option<u64> {
    let parsed = value.parse::<f64>().ok()?;
    if !parsed.is_finite() || parsed <= 0.0 {
        return None;
    }
    Some((parsed * 100.0).round() as u64)
}

fn escape_json(value: &str) -> String {
    let mut escaped = String::new();
    for character in value.chars() {
        match character {
            '"' | '\\' => {
                escaped.push('\\');
                escaped.push(character);
            }
            character if character.is_ascii_graphic() || character == ' ' => {
                escaped.push(character);
            }
            _ => escaped.push('?'),
        }
    }
    escaped
}

#[cfg(test)]
mod tests {
    use super::{
        ABI_VERSION, DEFAULT_ANIMATION, DIAGRAM_TYPE, ROOTS, lower_reference_frames,
        parse_reference_sankey,
    };

    #[test]
    fn parse_reference_sankey_accepts_quoted_csv() {
        let document = parse_reference_sankey(
            "sankey-beta\n\"North America\",Pipeline,12.5\nPipeline,\"Closed, Won\",9\n%% comment\n",
        )
        .unwrap();

        assert_eq!(document.header, "sankey-beta");
        assert_eq!(document.links.len(), 2);
        assert_eq!(document.links[0].source, "North America");
        assert_eq!(document.links[0].value_units, 1250);
        assert_eq!(document.links[1].target, "Closed, Won");
        assert_eq!(
            lower_reference_frames(&document),
            "{\"type\":\"sankey\",\"animation\":\"none\",\"links\":[{\"source\":\"North America\",\"target\":\"Pipeline\",\"valueUnits\":1250,\"value\":\"12.5\"},{\"source\":\"Pipeline\",\"target\":\"Closed, Won\",\"valueUnits\":900,\"value\":\"9\"}]}"
        );
        assert_eq!(ABI_VERSION, "1.0");
        assert_eq!(DIAGRAM_TYPE, "sankey");
        assert_eq!(DEFAULT_ANIMATION, "none");
        assert_eq!(ROOTS, ["sankey", "sankey-beta"]);
    }

    #[test]
    fn parse_reference_sankey_rejects_invalid_input() {
        assert!(
            parse_reference_sankey("")
                .unwrap_err()
                .contains("missing sankey header")
        );
        assert!(
            parse_reference_sankey("flowchart\nA,B,1")
                .unwrap_err()
                .contains("expected sankey header")
        );
        assert!(
            parse_reference_sankey("sankey\nA,B,0")
                .unwrap_err()
                .contains("expected positive sankey value")
        );
    }
}
