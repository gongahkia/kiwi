use pdf_writer::{Content, Finish, Name, Pdf, Rect, Ref, Str};

pub const PLUGIN_NAME: &str = "kumeyuri-render-pdf";
pub const ABI_VERSION: &str = "1.0";
pub const FORMAT: &str = "pdf";
pub const MEDIA_TYPE: &str = "application/pdf";
pub const EXTENSION: &str = "pdf";

#[must_use]
pub fn render_reference_pdf(title: Option<&str>) -> Vec<u8> {
    let title = title.unwrap_or("kumeyuri diagram");
    let title = pdf_ascii(title);
    let subtitle = pdf_ascii("render-backend plugin via kumeyuri ABI 1.0");

    let catalog_id = Ref::new(1);
    let page_tree_id = Ref::new(2);
    let page_id = Ref::new(3);
    let font_id = Ref::new(4);
    let content_id = Ref::new(5);
    let font_name = Name(b"F1");

    let mut pdf = Pdf::new();
    pdf.catalog(catalog_id).pages(page_tree_id);
    pdf.pages(page_tree_id).kids([page_id]).count(1);
    pdf.type1_font(font_id).base_font(Name(b"Helvetica"));

    let mut page = pdf.page(page_id);
    page.media_box(Rect::new(0.0, 0.0, 612.0, 792.0));
    page.parent(page_tree_id);
    page.contents(content_id);
    page.resources().fonts().pair(font_name, font_id);
    page.finish();

    let mut content = Content::new();
    content.begin_text();
    content.set_font(font_name, 18.0);
    content.next_line(72.0, 720.0);
    content.show(Str(&title));
    content.set_font(font_name, 10.0);
    content.next_line(0.0, -24.0);
    content.show(Str(&subtitle));
    content.end_text();
    pdf.stream(content_id, &content.finish());

    pdf.finish()
}

fn pdf_ascii(value: &str) -> Vec<u8> {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_graphic() || character == ' ' {
                character as u8
            } else {
                b'?'
            }
        })
        .collect()
}

#[must_use]
pub fn render_reference_pdf_from_text(title: Option<&str>, text_frame: &str) -> Vec<u8> {
    let title = title.unwrap_or("kumeyuri diagram");
    let frame = text_frame
        .lines()
        .take(28)
        .map(pdf_ascii)
        .collect::<Vec<_>>();

    let catalog_id = Ref::new(1);
    let page_tree_id = Ref::new(2);
    let page_id = Ref::new(3);
    let font_id = Ref::new(4);
    let content_id = Ref::new(5);
    let font_name = Name(b"F1");

    let mut pdf = Pdf::new();
    pdf.catalog(catalog_id).pages(page_tree_id);
    pdf.pages(page_tree_id).kids([page_id]).count(1);
    pdf.type1_font(font_id).base_font(Name(b"Courier"));

    let mut page = pdf.page(page_id);
    page.media_box(Rect::new(0.0, 0.0, 612.0, 792.0));
    page.parent(page_tree_id);
    page.contents(content_id);
    page.resources().fonts().pair(font_name, font_id);
    page.finish();

    let mut content = Content::new();
    content.begin_text();
    content.set_font(font_name, 14.0);
    content.next_line(72.0, 730.0);
    let title = pdf_ascii(title);
    content.show(Str(&title));
    content.set_font(font_name, 8.0);
    content.next_line(0.0, -22.0);
    for line in frame {
        if !line.is_empty() {
            content.show(Str(&line));
        }
        content.next_line(0.0, -10.0);
    }
    content.end_text();
    pdf.stream(content_id, &content.finish());

    pdf.finish()
}

#[cfg(test)]
mod tests {
    use super::{
        EXTENSION, FORMAT, MEDIA_TYPE, render_reference_pdf, render_reference_pdf_from_text,
    };

    #[test]
    fn render_reference_pdf_outputs_valid_pdf_markers_from_pdf_writer() {
        let pdf = render_reference_pdf(Some("A )demo( \\ diagram"));
        let text = String::from_utf8_lossy(&pdf);

        assert!(text.starts_with("%PDF-1."));
        assert!(text.contains("/Type /Catalog"));
        assert!(text.contains("/BaseFont /Helvetica"));
        assert!(text.contains("A \\)demo\\( \\\\ diagram"));
        assert!(text.ends_with("%%EOF"));
        assert_eq!(FORMAT, "pdf");
        assert_eq!(MEDIA_TYPE, "application/pdf");
        assert_eq!(EXTENSION, "pdf");
    }

    #[test]
    fn render_reference_pdf_sample_is_deterministic() {
        let title = include_str!("../tests/fixtures/sample-title.txt").trim_end();
        assert_eq!(
            render_reference_pdf(Some(title)),
            render_reference_pdf(Some(title))
        );
    }

    #[test]
    fn render_reference_pdf_from_text_uses_monospace_frame_lines() {
        let pdf = render_reference_pdf_from_text(Some("Frame"), "+---+\n| A |\n+---+");
        let text = String::from_utf8_lossy(&pdf);

        assert!(text.contains("/BaseFont /Courier"));
        assert!(text.contains("+---+"));
        assert!(text.contains("| A |"));
    }
}
