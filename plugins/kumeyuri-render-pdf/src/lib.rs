pub const PLUGIN_NAME: &str = "kumeyuri-render-pdf";
pub const ABI_VERSION: &str = "1.0";
pub const FORMAT: &str = "pdf";
pub const MEDIA_TYPE: &str = "application/pdf";
pub const EXTENSION: &str = "pdf";

#[must_use]
pub fn render_reference_pdf(title: Option<&str>) -> Vec<u8> {
    let title = title.unwrap_or("kumeyuri diagram");
    let escaped_title = escape_pdf_text(title);
    let stream = format!("BT /F1 18 Tf 72 720 Td ({escaped_title}) Tj ET\n");
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>".to_owned(),
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_owned(),
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>".to_owned(),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".to_owned(),
        format!("<< /Length {} >>\nstream\n{}endstream", stream.len(), stream),
    ];

    let mut pdf = Vec::from("%PDF-1.4\n".as_bytes());
    let mut offsets = Vec::with_capacity(objects.len());
    for (index, object) in objects.iter().enumerate() {
        offsets.push(pdf.len());
        pdf.extend_from_slice(format!("{} 0 obj\n{}\nendobj\n", index + 1, object).as_bytes());
    }
    let xref_offset = pdf.len();
    pdf.extend_from_slice(
        format!("xref\n0 {}\n0000000000 65535 f \n", objects.len() + 1).as_bytes(),
    );
    for offset in offsets {
        pdf.extend_from_slice(format!("{offset:010} 00000 n \n").as_bytes());
    }
    pdf.extend_from_slice(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n",
            objects.len() + 1
        )
        .as_bytes(),
    );
    pdf
}

fn escape_pdf_text(value: &str) -> String {
    let mut escaped = String::new();
    for character in value.chars() {
        match character {
            '(' | ')' | '\\' => {
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
    use super::{EXTENSION, FORMAT, MEDIA_TYPE, render_reference_pdf};

    #[test]
    fn render_reference_pdf_outputs_valid_pdf_markers() {
        let pdf = render_reference_pdf(Some("A (demo) \\ diagram"));
        let text = String::from_utf8(pdf).unwrap();

        assert!(text.starts_with("%PDF-1.4\n"));
        assert!(text.contains("/Type /Catalog"));
        assert!(text.contains("A \\(demo\\) \\\\ diagram"));
        assert!(text.ends_with("%%EOF\n"));
        assert_eq!(FORMAT, "pdf");
        assert_eq!(MEDIA_TYPE, "application/pdf");
        assert_eq!(EXTENSION, "pdf");
    }
}
