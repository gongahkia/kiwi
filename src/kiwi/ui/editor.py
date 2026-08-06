"""Headless immutable state for the intentionally small source editor."""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass, field, replace


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
class EditorState:
    """Headless editor selection and viewport state over an immutable text buffer."""

    buffer: TextBuffer
    selection: TextSelection
    scroll: ScrollPosition = field(default_factory=ScrollPosition)

    @classmethod
    def from_text(cls, text: str) -> EditorState:
        """Create an editor with its cursor and viewport at source origin."""
        return cls(TextBuffer(text), TextSelection(0, 0))

    def __post_init__(self) -> None:
        if not isinstance(self.buffer, TextBuffer):
            raise TypeError("editor buffer must be a text buffer")
        if not isinstance(self.selection, TextSelection):
            raise TypeError("editor selection must be a text selection")
        if not isinstance(self.scroll, ScrollPosition):
            raise TypeError("editor scroll must be a scroll position")
        _require_offset(self.selection.anchor, self.buffer.character_count)
        _require_offset(self.selection.focus, self.buffer.character_count)
        self.buffer.line_index.line_bounds(self.scroll.line)
        if self.scroll.column > self._max_document_column:
            raise ValueError("scroll column exceeds document width")

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
    def _max_document_column(self) -> int:
        return max(
            self.buffer.line_index.max_column(line)
            for line in range(1, self.buffer.line_index.line_count + 1)
        )


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
