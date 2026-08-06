"""Bitmap rendering for archive-bound source panes and source-map highlights."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.dsl.source import SourceFile, SourceSpan
from kiwi.render.bitmap_font import BitmapFont
from kiwi.render.source_view import (
    DEFAULT_SOURCE_PALETTE,
    SourcePalette,
    SourceRenderResult,
    render_source,
)
from kiwi.ui.historical_source import HistoricalSourcePane


def _color(color: tuple[int, int, int]) -> None:
    if (
        not isinstance(color, tuple)
        or len(color) != 3
        or any(
            not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 255
            for value in color
        )
    ):
        raise ValueError("historical source colour must be an RGB tuple")


@dataclass(frozen=True, slots=True)
class HistoricalSourcePalette:
    heading: tuple[int, int, int] = (110, 177, 223)
    highlight: tuple[int, int, int] = (245, 189, 74)

    def __post_init__(self) -> None:
        _color(self.heading)
        _color(self.highlight)


DEFAULT_HISTORICAL_SOURCE_PALETTE = HistoricalSourcePalette()


@dataclass(frozen=True, slots=True)
class HistoricalSourceRenderResult:
    source: SourceRenderResult
    highlight_count: int
    height: int


def render_historical_source_pane(
    surface: pygame.Surface,
    font: BitmapFont,
    pane: HistoricalSourcePane,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: HistoricalSourcePalette = DEFAULT_HISTORICAL_SOURCE_PALETTE,
    source_palette: SourcePalette = DEFAULT_SOURCE_PALETTE,
) -> HistoricalSourceRenderResult:
    """Draw only archive-bound source and its exact selected expression spans."""
    if not isinstance(surface, pygame.Surface) or not isinstance(font, BitmapFont):
        raise TypeError("historical source rendering requires a pygame surface and bitmap font")
    if not isinstance(pane, HistoricalSourcePane):
        raise TypeError("historical source rendering requires a historical source pane")
    if (
        not isinstance(origin, tuple)
        or len(origin) != 2
        or any(not isinstance(value, int) or isinstance(value, bool) for value in origin)
    ):
        raise TypeError("historical source rendering origin must be an integer pair")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("historical source rendering scale must be positive")
    if not isinstance(palette, HistoricalSourcePalette) or not isinstance(
        source_palette, SourcePalette
    ):
        raise TypeError("historical source rendering requires source palettes")
    line_height = font.measure("M", scale)[1]
    surface.blit(
        font.render(
            f"historical e{pane.entity_id.value}: {pane.source.file_id.value}",
            palette.heading,
            scale,
        ),
        origin,
    )
    source_origin = (origin[0], origin[1] + line_height)
    source_result = render_source(
        surface,
        font,
        pane.source,
        source_origin,
        scale=scale,
        palette=source_palette,
    )
    for span in pane.highlighted_spans:
        _draw_highlight(
            surface,
            font,
            pane.source,
            span,
            source_origin,
            line_height,
            scale,
            palette.highlight,
        )
    return HistoricalSourceRenderResult(
        source_result,
        len(pane.highlighted_spans),
        line_height + source_result.height,
    )


def _draw_highlight(
    surface: pygame.Surface,
    font: BitmapFont,
    source: SourceFile,
    span: SourceSpan,
    origin: tuple[int, int],
    line_height: int,
    scale: int,
    color: tuple[int, int, int],
) -> None:
    start, end = source.positions_of(span)
    lines = source.text.split("\n")
    if span.byte_length == 0:
        _draw_highlight_segment(
            surface,
            font,
            lines[start.line - 1].removesuffix("\r"),
            start.column,
            start.column,
            origin,
            start.line,
            line_height,
            scale,
            color,
        )
        return
    for line_number in range(start.line, end.line + 1):
        line = lines[line_number - 1].removesuffix("\r")
        start_column = start.column if line_number == start.line else 1
        end_column = end.column if line_number == end.line else len(line) + 1
        if start_column == end_column:
            continue
        _draw_highlight_segment(
            surface,
            font,
            line,
            start_column,
            end_column,
            origin,
            line_number,
            line_height,
            scale,
            color,
        )


def _draw_highlight_segment(
    surface: pygame.Surface,
    font: BitmapFont,
    line: str,
    start_column: int,
    end_column: int,
    origin: tuple[int, int],
    line_number: int,
    line_height: int,
    scale: int,
    color: tuple[int, int, int],
) -> None:
    start = origin[0] + font.measure(line[: start_column - 1].expandtabs(4), scale)[0]
    width = font.measure(line[start_column - 1 : end_column - 1].expandtabs(4), scale)[0]
    minimum_width = font.measure("M", scale)[0]
    y = origin[1] + line_number * line_height - 1
    pygame.draw.line(surface, color, (start, y), (start + max(width, minimum_width) - 1, y))
