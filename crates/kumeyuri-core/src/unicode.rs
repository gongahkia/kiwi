//! Unicode display-width, grapheme, and bidirectional text helpers.

use unicode_bidi::BidiInfo;
use unicode_segmentation::UnicodeSegmentation;
use unicode_width::UnicodeWidthStr;

/// Return the terminal display width of a string in character cells.
#[must_use]
pub fn display_width(text: &str) -> usize {
    UnicodeWidthStr::width(text)
}

/// Return the terminal display width as `i32`, saturating at `i32::MAX`.
#[must_use]
pub fn display_width_i32(text: &str) -> i32 {
    i32::try_from(display_width(text)).unwrap_or(i32::MAX)
}

/// Reorder one logical text line into visual order for BiDi display.
#[must_use]
pub fn bidi_visual_order_line(text: &str) -> String {
    let bidi = BidiInfo::new(text, None);
    let Some(paragraph) = bidi.paragraphs.first() else {
        return text.to_owned();
    };
    bidi.reorder_line(paragraph, 0..text.len()).into_owned()
}

/// Truncate a string to a maximum display width without splitting graphemes.
#[must_use]
pub fn truncate_display_width(text: &str, max_width: usize) -> String {
    let mut output = String::new();
    let mut width = 0usize;
    for grapheme in UnicodeSegmentation::graphemes(text, true) {
        let grapheme_width = display_width(grapheme);
        if width + grapheme_width > max_width {
            break;
        }
        output.push_str(grapheme);
        width += grapheme_width;
    }
    output
}

/// Wrap text into display-width-limited lines without splitting graphemes.
#[must_use]
pub fn wrap_display_width_lines(text: &str, max_width: usize) -> Vec<String> {
    if text.is_empty() {
        return Vec::new();
    }
    let mut lines = Vec::new();
    for line in text.lines() {
        wrap_display_width_line(line, max_width, &mut lines);
    }
    lines
}

fn wrap_display_width_line(line: &str, max_width: usize, lines: &mut Vec<String>) {
    if display_width(line) <= max_width {
        lines.push(line.to_owned());
        return;
    }
    let mut current = String::new();
    let mut current_width = 0usize;
    for word in line.split_whitespace() {
        let word_width = display_width(word);
        if current.is_empty() && word_width <= max_width {
            current.push_str(word);
            current_width = word_width;
        } else if !current.is_empty() && current_width + 1 + word_width <= max_width {
            current.push(' ');
            current.push_str(word);
            current_width += 1 + word_width;
        } else {
            if !current.is_empty() {
                lines.push(std::mem::take(&mut current));
                current_width = 0;
            }
            push_wrapped_word(word, max_width, lines, &mut current, &mut current_width);
        }
    }
    if !current.is_empty() {
        lines.push(current);
    } else if lines.is_empty() {
        lines.push(String::new());
    }
}

fn push_wrapped_word(
    word: &str,
    max_width: usize,
    lines: &mut Vec<String>,
    current: &mut String,
    current_width: &mut usize,
) {
    if display_width(word) <= max_width {
        current.push_str(word);
        *current_width = display_width(word);
        return;
    }

    let mut chunk = String::new();
    let mut chunk_width = 0usize;
    for grapheme in UnicodeSegmentation::graphemes(word, true) {
        let grapheme_width = display_width(grapheme);
        if !chunk.is_empty() && chunk_width + grapheme_width > max_width {
            lines.push(std::mem::take(&mut chunk));
            chunk_width = 0;
        }
        if chunk.is_empty() && grapheme_width > max_width {
            lines.push(grapheme.to_owned());
            continue;
        }
        chunk.push_str(grapheme);
        chunk_width += grapheme_width;
        if chunk_width == max_width {
            lines.push(std::mem::take(&mut chunk));
            chunk_width = 0;
        }
    }
    if !chunk.is_empty() {
        current.push_str(&chunk);
        *current_width = chunk_width;
    }
}

#[cfg(test)]
mod tests {
    use super::{
        bidi_visual_order_line, display_width, truncate_display_width, wrap_display_width_lines,
    };

    #[test]
    fn bidi_visual_order_reorders_rtl_runs() {
        assert_eq!(bidi_visual_order_line("A אבג"), "A גבא");
        assert_eq!(bidi_visual_order_line("ABC"), "ABC");
    }

    #[test]
    fn display_width_counts_cells_not_codepoints() {
        assert_eq!(display_width("ascii"), 5);
        assert_eq!(display_width("漢字"), 4);
        assert_eq!(display_width("e\u{301}"), 1);
    }

    #[test]
    fn truncate_display_width_preserves_graphemes() {
        assert_eq!(truncate_display_width("漢字abc", 4), "漢字");
        assert_eq!(
            truncate_display_width("e\u{301}e\u{301}e\u{301}", 2),
            "e\u{301}e\u{301}"
        );
    }

    #[test]
    fn wrap_display_width_preserves_graphemes() {
        assert_eq!(
            wrap_display_width_lines("alpha 漢字 beta", 6),
            vec!["alpha", "漢字", "beta"]
        );
        assert_eq!(
            wrap_display_width_lines("e\u{301}e\u{301}e\u{301}", 2),
            vec!["e\u{301}e\u{301}", "e\u{301}"]
        );
    }
}
