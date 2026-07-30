"""Immutable source-coordinate values for the Kiwi DSL."""

from __future__ import annotations

from bisect import bisect_left, bisect_right
from dataclasses import dataclass, field


@dataclass(frozen=True, slots=True, order=True)
class SourceFileId:
    """A stable logical identifier for one source file."""

    value: str

    def __post_init__(self) -> None:
        if not isinstance(self.value, str) or not self.value:
            raise ValueError("source file ID must be a non-empty string")


@dataclass(frozen=True, slots=True, order=True)
class ByteOffset:
    """A non-negative UTF-8 byte offset."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool) or self.value < 0:
            raise ValueError("byte offset must be a non-negative integer")


@dataclass(frozen=True, slots=True)
class SourcePosition:
    """A source coordinate with one-based line and Unicode-code-point column."""

    offset: ByteOffset
    line: int
    column: int

    def __post_init__(self) -> None:
        if self.line < 1 or self.column < 1:
            raise ValueError("source position line and column must be positive")


@dataclass(frozen=True, slots=True)
class SourceSpan:
    """A half-open source range in one source file."""

    file_id: SourceFileId
    start: ByteOffset
    end: ByteOffset

    def __post_init__(self) -> None:
        if self.end < self.start:
            raise ValueError("source span end precedes start")

    @property
    def byte_length(self) -> int:
        """Return the number of bytes in this range."""
        return self.end.value - self.start.value

    def contains(self, offset: ByteOffset) -> bool:
        """Return whether an offset lies inside this half-open range."""
        return self.start <= offset < self.end


@dataclass(frozen=True, slots=True)
class LineIndex:
    """Map UTF-8 byte offsets to source positions without retaining source text."""

    _byte_boundaries: tuple[int, ...]
    _line_starts: tuple[int, ...]
    _line_start_character_indexes: tuple[int, ...]

    @classmethod
    def from_text(cls, text: str) -> LineIndex:
        """Build an index for Unicode text encoded as UTF-8."""
        byte_boundaries = [0]
        line_starts = [0]
        line_start_character_indexes = [0]
        byte_offset = 0
        for character_index, character in enumerate(text, start=1):
            byte_offset += len(character.encode("utf-8"))
            byte_boundaries.append(byte_offset)
            if character == "\n":
                line_starts.append(byte_offset)
                line_start_character_indexes.append(character_index)
        return cls(
            tuple(byte_boundaries),
            tuple(line_starts),
            tuple(line_start_character_indexes),
        )

    @property
    def byte_length(self) -> int:
        """Return the UTF-8 byte length of indexed source."""
        return self._byte_boundaries[-1]

    def position_of(self, offset: ByteOffset) -> SourcePosition:
        """Return the position at an exact UTF-8 code-point boundary."""
        boundary_index = bisect_left(self._byte_boundaries, offset.value)
        if (
            boundary_index == len(self._byte_boundaries)
            or self._byte_boundaries[boundary_index] != offset.value
        ):
            raise ValueError("byte offset is outside source or splits a UTF-8 code point")
        line_index = bisect_right(self._line_starts, offset.value) - 1
        column = boundary_index - self._line_start_character_indexes[line_index] + 1
        return SourcePosition(offset, line_index + 1, column)


@dataclass(frozen=True, slots=True)
class SourceFile:
    """In-memory DSL source and its derived UTF-8 line index."""

    file_id: SourceFileId
    text: str
    line_index: LineIndex = field(init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.text, str):
            raise ValueError("source text must be a string")
        object.__setattr__(self, "line_index", LineIndex.from_text(self.text))

    def position_of(self, offset: ByteOffset) -> SourcePosition:
        """Return a validated position in this source file."""
        return self.line_index.position_of(offset)

    def span(self, start: ByteOffset, end: ByteOffset) -> SourceSpan:
        """Construct a validated half-open span in this source file."""
        self.position_of(start)
        self.position_of(end)
        return SourceSpan(self.file_id, start, end)

    def positions_of(self, span: SourceSpan) -> tuple[SourcePosition, SourcePosition]:
        """Return validated start and end positions for a span in this file."""
        if span.file_id != self.file_id:
            raise ValueError("source span belongs to a different source file")
        return (self.position_of(span.start), self.position_of(span.end))
