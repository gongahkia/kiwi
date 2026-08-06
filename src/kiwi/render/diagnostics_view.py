"""Bitmap rendering for inline source markers and structured diagnostic panels."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.dsl.diagnostics import DiagnosticSeverity
from kiwi.dsl.source import SourceFile
from kiwi.render.bitmap_font import BitmapFont
from kiwi.ui.diagnostics import DiagnosticPresentation, InlineDiagnostic, PanelDiagnostic


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("diagnostic palette color must be a three-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in color):
        raise ValueError("diagnostic palette color components must be integers")
    if any(component < 0 or component > 255 for component in color):
        raise ValueError("diagnostic palette color components must be 0 through 255")


@dataclass(frozen=True, slots=True)
class DiagnosticPalette:
    """Fixed terminal colours for error and warning diagnostic presentation."""

    error: tuple[int, int, int] = (239, 99, 99)
    warning: tuple[int, int, int] = (245, 189, 74)

    def __post_init__(self) -> None:
        _validate_color(self.error)
        _validate_color(self.warning)

    def color_for(self, severity: DiagnosticSeverity) -> tuple[int, int, int]:
        """Return a colour for one structured diagnostic severity."""
        if not isinstance(severity, DiagnosticSeverity):
            raise TypeError("diagnostic palette severity must be a diagnostic severity")
        return self.error if severity is DiagnosticSeverity.ERROR else self.warning


DEFAULT_DIAGNOSTIC_PALETTE = DiagnosticPalette()


@dataclass(frozen=True, slots=True)
class DiagnosticRenderResult:
    """The count and logical height of a rendered diagnostic region."""

    entry_count: int
    height: int


def render_inline_diagnostics(
    surface: pygame.Surface,
    font: BitmapFont,
    source: SourceFile,
    presentation: DiagnosticPresentation,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: DiagnosticPalette = DEFAULT_DIAGNOSTIC_PALETTE,
) -> DiagnosticRenderResult:
    """Draw source-aligned one-pixel diagnostic underlines onto an existing surface."""
    _validate_inputs(surface, font, source, presentation, origin, scale, palette)
    line_height = font.measure("M", scale)[1]
    lines = source.text.split("\n")
    for marker in presentation.inline:
        _draw_marker(surface, font, lines, marker, origin, line_height, scale, palette)
    return DiagnosticRenderResult(
        len(presentation.inline), (source.text.count("\n") + 1) * line_height
    )


def render_diagnostic_panel(
    surface: pygame.Surface,
    font: BitmapFont,
    presentation: DiagnosticPresentation,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: DiagnosticPalette = DEFAULT_DIAGNOSTIC_PALETTE,
) -> DiagnosticRenderResult:
    """Render canonical panel rows with code, source position, and diagnostic message."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("diagnostic rendering requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("diagnostic rendering requires a bitmap font")
    if not isinstance(presentation, DiagnosticPresentation):
        raise TypeError("diagnostic rendering requires a diagnostic presentation")
    _validate_origin(origin)
    _validate_scale(scale)
    if not isinstance(palette, DiagnosticPalette):
        raise TypeError("diagnostic rendering palette must be a diagnostic palette")
    line_height = font.measure("M", scale)[1]
    for index, entry in enumerate(presentation.panel):
        rendered = font.render(
            _panel_text(entry), palette.color_for(entry.diagnostic.severity), scale
        )
        surface.blit(rendered, (origin[0], origin[1] + index * line_height))
    return DiagnosticRenderResult(len(presentation.panel), len(presentation.panel) * line_height)


def _draw_marker(
    surface: pygame.Surface,
    font: BitmapFont,
    lines: list[str],
    marker: InlineDiagnostic,
    origin: tuple[int, int],
    line_height: int,
    scale: int,
    palette: DiagnosticPalette,
) -> None:
    line = lines[marker.line - 1]
    start_index = marker.start_column - 1
    end_index = marker.end_column - 1
    start = origin[0] + font.measure(line[:start_index].expandtabs(4), scale)[0]
    length = font.measure(line[start_index:end_index].expandtabs(4), scale)[0]
    minimum_width = font.measure("M", scale)[0]
    end = start + max(length, minimum_width)
    y = origin[1] + marker.line * line_height - 1
    pygame.draw.line(
        surface, palette.color_for(marker.diagnostic.severity), (start, y), (end - 1, y)
    )


def _panel_text(entry: PanelDiagnostic) -> str:
    diagnostic = entry.diagnostic
    return f"{diagnostic.code} L{entry.line}:C{entry.column} {diagnostic.message}"


def _validate_inputs(
    surface: pygame.Surface,
    font: BitmapFont,
    source: SourceFile,
    presentation: DiagnosticPresentation,
    origin: tuple[int, int],
    scale: int,
    palette: DiagnosticPalette,
) -> None:
    if not isinstance(surface, pygame.Surface):
        raise TypeError("diagnostic rendering requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("diagnostic rendering requires a bitmap font")
    if not isinstance(source, SourceFile):
        raise TypeError("inline diagnostic rendering requires a source file")
    if not isinstance(presentation, DiagnosticPresentation):
        raise TypeError("diagnostic rendering requires a diagnostic presentation")
    if presentation.source_file_id != source.file_id:
        raise ValueError("inline diagnostic presentation belongs to a different source file")
    _validate_origin(origin)
    _validate_scale(scale)
    if not isinstance(palette, DiagnosticPalette):
        raise TypeError("diagnostic rendering palette must be a diagnostic palette")


def _validate_origin(origin: tuple[int, int]) -> None:
    if not isinstance(origin, tuple) or len(origin) != 2:
        raise TypeError("diagnostic rendering origin must be a two-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in origin):
        raise TypeError("diagnostic rendering origin components must be integers")


def _validate_scale(scale: int) -> None:
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("diagnostic rendering scale must be a positive integer")
