"""Headless immutable state for the intentionally small source editor."""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass, field, replace

DEFAULT_HISTORY_LIMIT = 100


@dataclass(frozen=True, slots=True, order=True)
class TextPosition:
    """One-based Unicode-code-point position in editable source text."""

    line: int
    column: int

    def __post_init__(self) -> None:
        _require_positive(self.line, "text position line")
        _require_positive(self.column, "text position column")


@dataclass(frozen=True, slots=True)
class LineIndex:
    """Map Python string offsets and one-based source positions without rendering."""

    _starts: tuple[int, ...]
    _text_length: int

    @classmethod
    def from_text(cls, text: str) -> LineIndex:
        if not isinstance(text, str):
            raise TypeError("line index text must be a string")
        starts = [0]
        for offset, character in enumerate(text):
            if character == "\n":
                starts.append(offset + 1)
        return cls(tuple(starts), len(text))

    @property
    def line_count(self) -> int:
        """Return the number of logical lines, including a trailing empty line."""
        return len(self._starts)

    @property
    def character_count(self) -> int:
        """Return the Unicode-code-point length of the indexed text."""
        return self._text_length

    def position_of(self, offset: int) -> TextPosition:
        """Return the one-based position at a validated code-point boundary."""
        _require_offset(offset, self._text_length)
        line_index = bisect_right(self._starts, offset) - 1
        return TextPosition(line_index + 1, offset - self._starts[line_index] + 1)

    def offset_of(self, position: TextPosition) -> int:
        """Return the validated code-point offset for one source position."""
        if not isinstance(position, TextPosition):
            raise TypeError("line index position must be a text position")
        start, end = self.line_bounds(position.line)
        offset = start + position.column - 1
        if offset > end:
            raise ValueError("text position column exceeds line length")
        return offset

    def line_bounds(self, line: int) -> tuple[int, int]:
        """Return the half-open content bounds for one line, excluding its newline."""
        _require_positive(line, "line number")
        line_index = line - 1
        if line_index >= self.line_count:
            raise ValueError("line number exceeds line count")
        start = self._starts[line_index]
        if line_index + 1 == self.line_count:
            return (start, self._text_length)
        return (start, self._starts[line_index + 1] - 1)

    def max_column(self, line: int) -> int:
        """Return the one-past-end column accepted for one line."""
        start, end = self.line_bounds(line)
        return end - start + 1


@dataclass(frozen=True, slots=True)
class TextBuffer:
    """Unicode source text with a derived line index for editor navigation."""

    text: str
    line_index: LineIndex = field(init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.text, str):
            raise TypeError("text buffer text must be a string")
        object.__setattr__(self, "line_index", LineIndex.from_text(self.text))

    @property
    def character_count(self) -> int:
        """Return the Unicode-code-point length of the buffer."""
        return self.line_index.character_count

    def position_of(self, offset: int) -> TextPosition:
        """Return the one-based position at one code-point offset."""
        return self.line_index.position_of(offset)

    def offset_of(self, position: TextPosition) -> int:
        """Return the code-point offset at one valid source position."""
        return self.line_index.offset_of(position)

    def line_text(self, line: int) -> str:
        """Return one line without a trailing newline."""
        start, end = self.line_index.line_bounds(line)
        return self.text[start:end]

    def replace(self, start: int, end: int, text: str) -> TextBuffer:
        """Return a buffer with one validated half-open range replaced by Unicode text."""
        _require_offset(start, self.character_count)
        _require_offset(end, self.character_count)
        if end < start:
            raise ValueError("replacement end precedes start")
        if not isinstance(text, str):
            raise TypeError("replacement text must be a string")
        return TextBuffer(self.text[:start] + text + self.text[end:])

    def insert(self, offset: int, text: str) -> TextBuffer:
        """Return a buffer with Unicode text inserted at one code-point offset."""
        return self.replace(offset, offset, text)

    def delete(self, start: int, end: int) -> TextBuffer:
        """Return a buffer without one validated half-open range."""
        return self.replace(start, end, "")


@dataclass(frozen=True, slots=True)
class TextSelection:
    """Anchor and focused cursor offsets; reversed selections remain explicit."""

    anchor: int
    focus: int

    def __post_init__(self) -> None:
        _require_non_negative(self.anchor, "selection anchor")
        _require_non_negative(self.focus, "selection focus")

    @property
    def start(self) -> int:
        """Return the lower bound of the selected range."""
        return min(self.anchor, self.focus)

    @property
    def end(self) -> int:
        """Return the exclusive upper bound of the selected range."""
        return max(self.anchor, self.focus)

    @property
    def is_empty(self) -> bool:
        """Return whether the selection contains no source text."""
        return self.anchor == self.focus


@dataclass(frozen=True, slots=True)
class ScrollPosition:
    """One-based top-left logical source position of the editor viewport."""

    line: int = 1
    column: int = 1

    def __post_init__(self) -> None:
        _require_positive(self.line, "scroll line")
        _require_positive(self.column, "scroll column")


@dataclass(frozen=True, slots=True)
class EditorCheckpoint:
    """One restorable non-authoritative editor state before or after an edit."""

    buffer: TextBuffer
    selection: TextSelection
    scroll: ScrollPosition

    def __post_init__(self) -> None:
        _validate_editor_values(self.buffer, self.selection, self.scroll)


@dataclass(frozen=True, slots=True)
class EditorState:
    """Headless editor selection and viewport state over an immutable text buffer."""

    buffer: TextBuffer
    selection: TextSelection
    scroll: ScrollPosition = field(default_factory=ScrollPosition)
    undo_history: tuple[EditorCheckpoint, ...] = ()
    redo_history: tuple[EditorCheckpoint, ...] = ()
    history_limit: int = DEFAULT_HISTORY_LIMIT

    @classmethod
    def from_text(cls, text: str) -> EditorState:
        """Create an editor with its cursor and viewport at source origin."""
        return cls(TextBuffer(text), TextSelection(0, 0))

    def __post_init__(self) -> None:
        _validate_editor_values(self.buffer, self.selection, self.scroll)
        _require_positive(self.history_limit, "editor history limit")
        _validate_history(self.undo_history, "undo history", self.history_limit)
        _validate_history(self.redo_history, "redo history", self.history_limit)

    @property
    def cursor_offset(self) -> int:
        """Return the focused cursor's code-point offset."""
        return self.selection.focus

    @property
    def cursor_position(self) -> TextPosition:
        """Return the focused cursor's one-based source position."""
        return self.buffer.position_of(self.cursor_offset)

    @property
    def selected_text(self) -> str:
        """Return the selected Unicode source text."""
        return self.buffer.text[self.selection.start : self.selection.end]

    @property
    def can_undo(self) -> bool:
        """Return whether a prior edit can be restored."""
        return bool(self.undo_history)

    @property
    def can_redo(self) -> bool:
        """Return whether an undone edit can be reapplied."""
        return bool(self.redo_history)

    def move_cursor(self, offset: int, *, extend_selection: bool = False) -> EditorState:
        """Move the focused cursor, optionally retaining the current selection anchor."""
        _require_offset(offset, self.buffer.character_count)
        anchor = self.selection.anchor if extend_selection else offset
        return replace(self, selection=TextSelection(anchor, offset))

    def move_to(self, position: TextPosition, *, extend_selection: bool = False) -> EditorState:
        """Move the focused cursor to one validated line-index position."""
        return self.move_cursor(self.buffer.offset_of(position), extend_selection=extend_selection)

    def select(self, anchor: int, focus: int) -> EditorState:
        """Set an explicit selection with either direction retained."""
        return replace(self, selection=TextSelection(anchor, focus))

    def replace_selection(self, text: str) -> EditorState:
        """Replace the selection and collapse the cursor after the inserted text."""
        if not isinstance(text, str):
            raise TypeError("replacement text must be a string")
        start = self.selection.start
        end = self.selection.end
        if start == end and not text:
            return self
        return self._record_edit(
            self.buffer.replace(start, end, text),
            TextSelection(start + len(text), start + len(text)),
        )

    def insert_text(self, text: str) -> EditorState:
        """Insert Unicode text, replacing an active selection when present."""
        return self.replace_selection(text)

    def delete_selection(self) -> EditorState:
        """Delete the selected text without changing state for an empty selection."""
        return self.replace_selection("")

    def delete_backward(self) -> EditorState:
        """Delete the selection or one preceding Unicode code point."""
        if not self.selection.is_empty:
            return self.delete_selection()
        if self.cursor_offset == 0:
            return self
        start = self.cursor_offset - 1
        return self._record_edit(
            self.buffer.delete(start, self.cursor_offset), TextSelection(start, start)
        )

    def delete_forward(self) -> EditorState:
        """Delete the selection or one following Unicode code point."""
        if not self.selection.is_empty:
            return self.delete_selection()
        if self.cursor_offset == self.buffer.character_count:
            return self
        return self._record_edit(
            self.buffer.delete(self.cursor_offset, self.cursor_offset + 1),
            TextSelection(self.cursor_offset, self.cursor_offset),
        )

    def insert_newline(self) -> EditorState:
        """Replace the selection with a newline and current-line leading whitespace."""
        line_start, _ = self.buffer.line_index.line_bounds(self.cursor_position.line)
        prefix = self.buffer.text[line_start : self.cursor_offset]
        indentation = prefix[: len(prefix) - len(prefix.lstrip(" \t"))]
        return self.replace_selection("\n" + indentation)

    def indent_selection(self, indentation: str = "    ") -> EditorState:
        """Prefix every selected logical line and preserve the selection direction."""
        _require_indentation(indentation)
        starts = self._selected_line_starts()
        text = self.buffer.text
        for start in reversed(starts):
            text = text[:start] + indentation + text[start:]
        return self._record_edit(
            TextBuffer(text),
            TextSelection(
                _offset_after_insertions(self.selection.anchor, starts, len(indentation)),
                _offset_after_insertions(self.selection.focus, starts, len(indentation)),
            ),
        )

    def outdent_selection(self, indentation: str = "    ") -> EditorState:
        """Remove one indentation unit or tab from each selected logical line."""
        _require_indentation(indentation)
        removals = tuple(
            (start, _indentation_length_at(self.buffer.text, start, indentation))
            for start in self._selected_line_starts()
        )
        removals = tuple((start, length) for start, length in removals if length > 0)
        if not removals:
            return self
        text = self.buffer.text
        for start, length in reversed(removals):
            text = text[:start] + text[start + length :]
        return self._record_edit(
            TextBuffer(text),
            TextSelection(
                _offset_after_removals(self.selection.anchor, removals),
                _offset_after_removals(self.selection.focus, removals),
            ),
        )

    def copy_selection(self) -> str:
        """Return selected text for a platform clipboard adapter without side effects."""
        return self.selected_text

    def cut_selection(self) -> ClipboardEdit:
        """Return copied text and an editor with its selection deleted."""
        return ClipboardEdit(self.delete_selection(), self.copy_selection())

    def paste_text(self, text: str) -> EditorState:
        """Insert text supplied by a platform clipboard adapter."""
        return self.insert_text(text)

    def undo(self) -> EditorState:
        """Restore the latest edit while retaining the present state for redo."""
        if not self.undo_history:
            return self
        previous = self.undo_history[-1]
        return EditorState(
            previous.buffer,
            previous.selection,
            previous.scroll,
            self.undo_history[:-1],
            _append_history(self.redo_history, self._checkpoint, self.history_limit),
            self.history_limit,
        )

    def redo(self) -> EditorState:
        """Reapply the latest undone edit while retaining the present state for undo."""
        if not self.redo_history:
            return self
        next_state = self.redo_history[-1]
        return EditorState(
            next_state.buffer,
            next_state.selection,
            next_state.scroll,
            _append_history(self.undo_history, self._checkpoint, self.history_limit),
            self.redo_history[:-1],
            self.history_limit,
        )

    def scroll_to(self, position: ScrollPosition) -> EditorState:
        """Set a validated top-left viewport location."""
        if not isinstance(position, ScrollPosition):
            raise TypeError("editor scroll must be a scroll position")
        return replace(self, scroll=position)

    def scroll_by(self, lines: int = 0, columns: int = 0) -> EditorState:
        """Move the viewport by bounded logical rows and columns."""
        _require_integer(lines, "scroll line delta")
        _require_integer(columns, "scroll column delta")
        return self.scroll_to(
            ScrollPosition(
                min(max(1, self.scroll.line + lines), self.buffer.line_index.line_count),
                min(max(1, self.scroll.column + columns), self._max_document_column),
            )
        )

    def reveal_cursor(self, visible_lines: int, visible_columns: int) -> EditorState:
        """Scroll only enough to place the focused cursor in the logical viewport."""
        _require_positive(visible_lines, "visible line count")
        _require_positive(visible_columns, "visible column count")
        cursor = self.cursor_position
        top = self.scroll.line
        left = self.scroll.column
        if cursor.line < top:
            top = cursor.line
        elif cursor.line >= top + visible_lines:
            top = cursor.line - visible_lines + 1
        if cursor.column < left:
            left = cursor.column
        elif cursor.column >= left + visible_columns:
            left = cursor.column - visible_columns + 1
        return self.scroll_to(ScrollPosition(top, left))

    @property
    def _checkpoint(self) -> EditorCheckpoint:
        return EditorCheckpoint(self.buffer, self.selection, self.scroll)

    def _record_edit(self, buffer: TextBuffer, selection: TextSelection) -> EditorState:
        return EditorState(
            buffer,
            selection,
            _clamp_scroll(buffer, self.scroll),
            _append_history(self.undo_history, self._checkpoint, self.history_limit),
            (),
            self.history_limit,
        )

    def _selected_line_starts(self) -> tuple[int, ...]:
        start_line = self.buffer.position_of(self.selection.start).line
        end_line = self.buffer.position_of(self.selection.end).line
        end_line_start, _ = self.buffer.line_index.line_bounds(end_line)
        if not self.selection.is_empty and self.selection.end == end_line_start:
            end_line -= 1
        return tuple(
            self.buffer.line_index.line_bounds(line)[0] for line in range(start_line, end_line + 1)
        )

    @property
    def _max_document_column(self) -> int:
        return _max_document_column(self.buffer)


@dataclass(frozen=True, slots=True)
class ClipboardEdit:
    """Text copied for a clipboard adapter and the resulting immutable editor state."""

    editor: EditorState
    text: str

    def __post_init__(self) -> None:
        if not isinstance(self.editor, EditorState):
            raise TypeError("clipboard edit requires an editor state")
        if not isinstance(self.text, str):
            raise TypeError("clipboard text must be a string")


def _validate_editor_values(
    buffer: TextBuffer,
    selection: TextSelection,
    scroll: ScrollPosition,
) -> None:
    if not isinstance(buffer, TextBuffer):
        raise TypeError("editor buffer must be a text buffer")
    if not isinstance(selection, TextSelection):
        raise TypeError("editor selection must be a text selection")
    if not isinstance(scroll, ScrollPosition):
        raise TypeError("editor scroll must be a scroll position")
    _require_offset(selection.anchor, buffer.character_count)
    _require_offset(selection.focus, buffer.character_count)
    buffer.line_index.line_bounds(scroll.line)
    if scroll.column > _max_document_column(buffer):
        raise ValueError("scroll column exceeds document width")


def _validate_history(
    history: tuple[EditorCheckpoint, ...],
    name: str,
    limit: int,
) -> None:
    if not isinstance(history, tuple):
        raise TypeError(f"{name} must be a tuple")
    if len(history) > limit:
        raise ValueError(f"{name} exceeds editor history limit")
    if any(not isinstance(checkpoint, EditorCheckpoint) for checkpoint in history):
        raise TypeError(f"{name} entries must be editor checkpoints")


def _max_document_column(buffer: TextBuffer) -> int:
    return max(
        buffer.line_index.max_column(line) for line in range(1, buffer.line_index.line_count + 1)
    )


def _clamp_scroll(buffer: TextBuffer, scroll: ScrollPosition) -> ScrollPosition:
    return ScrollPosition(
        min(scroll.line, buffer.line_index.line_count),
        min(scroll.column, _max_document_column(buffer)),
    )


def _append_history(
    history: tuple[EditorCheckpoint, ...],
    checkpoint: EditorCheckpoint,
    limit: int,
) -> tuple[EditorCheckpoint, ...]:
    return (*history, checkpoint)[-limit:]


def _offset_after_insertions(offset: int, starts: tuple[int, ...], length: int) -> int:
    return offset + sum(length for start in starts if start <= offset)


def _indentation_length_at(text: str, start: int, indentation: str) -> int:
    if text.startswith(indentation, start):
        return len(indentation)
    if text.startswith("\t", start):
        return 1
    return 0


def _offset_after_removals(offset: int, removals: tuple[tuple[int, int], ...]) -> int:
    removed = 0
    for start, length in removals:
        if offset <= start:
            break
        if offset < start + length:
            return start - removed
        removed += length
    return offset - removed


def _require_indentation(indentation: str) -> None:
    if not isinstance(indentation, str):
        raise TypeError("indentation must be a string")
    if not indentation or any(character not in " \t" for character in indentation):
        raise ValueError("indentation must contain only spaces or tabs")


def _require_integer(value: int, name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError(f"{name} must be an integer")


def _require_non_negative(value: int, name: str) -> None:
    _require_integer(value, name)
    if value < 0:
        raise ValueError(f"{name} must be non-negative")


def _require_positive(value: int, name: str) -> None:
    _require_integer(value, name)
    if value < 1:
        raise ValueError(f"{name} must be positive")


def _require_offset(value: int, maximum: int) -> None:
    _require_non_negative(value, "text offset")
    if value > maximum:
        raise ValueError("text offset exceeds buffer length")
