from __future__ import annotations

import pytest

from kiwi.ui.editor import EditorState, LineIndex, ScrollPosition, TextBuffer, TextPosition


def test_line_index_maps_unicode_offsets_and_trailing_empty_lines() -> None:
    buffer = TextBuffer("alpha\nβeta\n")

    assert buffer.line_index.line_count == 3
    assert buffer.character_count == 11
    assert buffer.position_of(0) == TextPosition(1, 1)
    assert buffer.position_of(5) == TextPosition(1, 6)
    assert buffer.position_of(6) == TextPosition(2, 1)
    assert buffer.position_of(11) == TextPosition(3, 1)
    assert buffer.offset_of(TextPosition(2, 2)) == 7
    assert buffer.line_text(1) == "alpha"
    assert buffer.line_text(2) == "βeta"
    assert buffer.line_text(3) == ""


def test_line_index_rejects_invalid_offsets_and_positions() -> None:
    index = LineIndex.from_text("one\ntwo")

    with pytest.raises(ValueError, match="exceeds buffer length"):
        index.position_of(8)
    with pytest.raises(ValueError, match="exceeds line length"):
        index.offset_of(TextPosition(1, 5))
    with pytest.raises(ValueError, match="exceeds line count"):
        index.line_bounds(3)


def test_editor_cursor_selection_and_scroll_remain_immutable() -> None:
    original = EditorState.from_text("alpha\nβeta\ngamma")
    selected = original.move_to(TextPosition(3, 3)).move_to(
        TextPosition(2, 2), extend_selection=True
    )
    scrolled = selected.scroll_to(ScrollPosition(2, 1)).scroll_by(columns=2)

    assert original.cursor_offset == 0
    assert original.selection.is_empty
    assert selected.cursor_position == TextPosition(2, 2)
    assert selected.selection.anchor == 13
    assert selected.selection.focus == 7
    assert selected.selection.start == 7
    assert selected.selection.end == 13
    assert selected.selected_text == "eta\nga"
    assert scrolled.scroll == ScrollPosition(2, 3)


def test_editor_reveals_cursor_and_clamps_relative_scrolling() -> None:
    editor = EditorState.from_text("one\ntwo\nthree\nfour\nfive")

    revealed = editor.move_to(TextPosition(5, 5)).reveal_cursor(2, 3)
    bounded = revealed.scroll_by(lines=100, columns=100).scroll_by(lines=-100, columns=-100)

    assert revealed.scroll == ScrollPosition(4, 3)
    assert bounded.scroll == ScrollPosition(1, 1)


def test_editor_rejects_out_of_range_selection_and_scroll() -> None:
    editor = EditorState.from_text("text")

    with pytest.raises(ValueError, match="exceeds buffer length"):
        editor.select(0, 5)
    with pytest.raises(ValueError, match="exceeds document width"):
        editor.scroll_to(ScrollPosition(1, 6))
