"""Bitmap rendering of immutable workbench compile-output rows."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.ui.compile_output import CompileOutput


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("compile output palette color must be a three-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in color):
        raise ValueError("compile output palette color components must be integers")
    if any(component < 0 or component > 255 for component in color):
        raise ValueError("compile output palette color components must be 0 through 255")


@dataclass(frozen=True, slots=True)
class CompileOutputPalette:
    """Fixed colours for successful and failed workbench compilation summaries."""

    success: tuple[int, int, int] = (111, 216, 168)
    failure: tuple[int, int, int] = (239, 99, 99)

    def __post_init__(self) -> None:
        _validate_color(self.success)
        _validate_color(self.failure)


DEFAULT_COMPILE_OUTPUT_PALETTE = CompileOutputPalette()


@dataclass(frozen=True, slots=True)
class CompileOutputRenderResult:
    """The immutable logical bounds of one compile-output panel render."""

    line_count: int
    height: int


def render_compile_output_panel(
    surface: pygame.Surface,
    font: BitmapFont,
    output: CompileOutput,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: CompileOutputPalette = DEFAULT_COMPILE_OUTPUT_PALETTE,
) -> CompileOutputRenderResult:
    """Render deterministic compile status rows onto an existing pygame surface."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("compile output rendering requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("compile output rendering requires a bitmap font")
    if not isinstance(output, CompileOutput):
        raise TypeError("compile output rendering requires compile output")
    _validate_origin(origin)
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("compile output rendering scale must be a positive integer")
    if not isinstance(palette, CompileOutputPalette):
        raise TypeError("compile output rendering palette must be a compile output palette")
    line_height = font.measure("M", scale)[1]
    color = palette.success if output.succeeded else palette.failure
    lines = output.panel_lines
    for index, line in enumerate(lines):
        surface.blit(font.render(line, color, scale), (origin[0], origin[1] + index * line_height))
    return CompileOutputRenderResult(len(lines), len(lines) * line_height)


def _validate_origin(origin: tuple[int, int]) -> None:
    if not isinstance(origin, tuple) or len(origin) != 2:
        raise TypeError("compile output rendering origin must be a two-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in origin):
        raise TypeError("compile output rendering origin components must be integers")
