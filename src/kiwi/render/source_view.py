"""Bitmap-font source rendering from immutable syntax spans."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.dsl.source import SourceFile
from kiwi.render.bitmap_font import BitmapFont
from kiwi.ui.syntax import SourceStyle, SyntaxSpan, syntax_spans


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("source palette color must be a three-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in color):
        raise ValueError("source palette color components must be integers")
    if any(component < 0 or component > 255 for component in color):
        raise ValueError("source palette color components must be 0 through 255")


@dataclass(frozen=True, slots=True)
class SourcePalette:
    """Fixed RGB source-token colours for the MVP terminal workbench."""

    default: tuple[int, int, int] = (206, 221, 231)
    keyword: tuple[int, int, int] = (111, 216, 238)
    literal: tuple[int, int, int] = (245, 189, 74)
    identifier: tuple[int, int, int] = (206, 221, 231)
    operator: tuple[int, int, int] = (244, 117, 94)
    punctuation: tuple[int, int, int] = (192, 201, 191)
    invalid: tuple[int, int, int] = (239, 99, 99)

    def __post_init__(self) -> None:
        for color in (
            self.default,
            self.keyword,
            self.literal,
            self.identifier,
            self.operator,
            self.punctuation,
            self.invalid,
        ):
            _validate_color(color)

    def color_for(self, style: SourceStyle) -> tuple[int, int, int]:
        """Return the RGB value assigned to one source style."""
        if not isinstance(style, SourceStyle):
            raise TypeError("source palette style must be a source style")
        return {
            SourceStyle.DEFAULT: self.default,
            SourceStyle.KEYWORD: self.keyword,
            SourceStyle.LITERAL: self.literal,
            SourceStyle.IDENTIFIER: self.identifier,
            SourceStyle.OPERATOR: self.operator,
            SourceStyle.PUNCTUATION: self.punctuation,
            SourceStyle.INVALID: self.invalid,
        }[style]


DEFAULT_SOURCE_PALETTE = SourcePalette()


@dataclass(frozen=True, slots=True)
class SourceRenderResult:
    """Deterministic logical layout bounds of one rendered source view."""

    line_count: int
    line_height: int
    width: int
    height: int


def render_source(
    surface: pygame.Surface,
    font: BitmapFont,
    source: SourceFile,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: SourcePalette = DEFAULT_SOURCE_PALETTE,
) -> SourceRenderResult:
    """Blit a source file with lexer-derived styles onto an existing pygame surface."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("source rendering requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("source rendering requires a bitmap font")
    if not isinstance(source, SourceFile):
        raise TypeError("source rendering requires a source file")
    _validate_origin(origin)
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("source rendering scale must be a positive integer")
    if not isinstance(palette, SourcePalette):
        raise TypeError("source rendering palette must be a source palette")
    line_height = font.measure("M", scale)[1]
    x, y = origin
    maximum_x = x
    for text, style in _styled_text(source, syntax_spans(source)):
        x, y, maximum_x = _render_text(
            surface,
            font,
            text,
            palette.color_for(style),
            x,
            y,
            origin[0],
            line_height,
            scale,
            maximum_x,
        )
    line_count = source.text.count("\n") + 1
    return SourceRenderResult(
        line_count, line_height, maximum_x - origin[0], line_count * line_height
    )


def _styled_text(
    source: SourceFile, spans: tuple[SyntaxSpan, ...]
) -> tuple[tuple[str, SourceStyle], ...]:
    source_bytes = source.text.encode("utf-8")
    cursor = 0
    fragments: list[tuple[str, SourceStyle]] = []
    for styled_span in spans:
        start = styled_span.span.start.value
        end = styled_span.span.end.value
        if start < cursor:
            raise ValueError("syntax spans overlap")
        if start > cursor:
            fragments.append((source_bytes[cursor:start].decode("utf-8"), SourceStyle.DEFAULT))
        fragments.append((source_bytes[start:end].decode("utf-8"), styled_span.style))
        cursor = end
    if cursor < len(source_bytes):
        fragments.append((source_bytes[cursor:].decode("utf-8"), SourceStyle.DEFAULT))
    return tuple(fragments)


def _render_text(
    surface: pygame.Surface,
    font: BitmapFont,
    text: str,
    color: tuple[int, int, int],
    x: int,
    y: int,
    line_start: int,
    line_height: int,
    scale: int,
    maximum_x: int,
) -> tuple[int, int, int]:
    for line in text.splitlines(keepends=True):
        content = line.removesuffix("\n").removesuffix("\r")
        if content:
            rendered = font.render(content.expandtabs(4), color, scale)
            surface.blit(rendered, (x, y))
            x += rendered.get_width()
            maximum_x = max(maximum_x, x)
        if line.endswith("\n") or line.endswith("\r"):
            x = line_start
            y += line_height
    return (x, y, maximum_x)


def _validate_origin(origin: tuple[int, int]) -> None:
    if not isinstance(origin, tuple) or len(origin) != 2:
        raise TypeError("source rendering origin must be a two-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in origin):
        raise TypeError("source rendering origin components must be integers")
