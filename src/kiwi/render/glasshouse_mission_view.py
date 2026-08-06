"""Bitmap tactical HUD for one non-authoritative Glasshouse execution view."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.render.camera import Camera
from kiwi.render.pygame_app import render_tactical_view
from kiwi.ui.glasshouse_mission import GlasshouseMissionPresentation


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("Glasshouse mission palette color must be an RGB tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in color):
        raise ValueError("Glasshouse mission palette color components must be integers")
    if any(component < 0 or component > 255 for component in color):
        raise ValueError("Glasshouse mission palette color components must be 0 through 255")


@dataclass(frozen=True, slots=True)
class GlasshouseMissionPalette:
    """Fixed mission HUD colours distinct from authority and input state."""

    panel: tuple[int, int, int] = (10, 14, 19)
    border: tuple[int, int, int] = (68, 119, 142)
    heading: tuple[int, int, int] = (111, 216, 238)
    normal: tuple[int, int, int] = (206, 221, 231)
    signal: tuple[int, int, int] = (111, 216, 168)
    warning: tuple[int, int, int] = (245, 189, 74)

    def __post_init__(self) -> None:
        for color in (
            self.panel,
            self.border,
            self.heading,
            self.normal,
            self.signal,
            self.warning,
        ):
            _validate_color(color)


DEFAULT_GLASSHOUSE_MISSION_PALETTE = GlasshouseMissionPalette()


@dataclass(frozen=True, slots=True)
class GlasshouseMissionRenderResult:
    """The fixed HUD row count for one rendered Glasshouse mission frame."""

    line_count: int

    def __post_init__(self) -> None:
        if not isinstance(self.line_count, int) or isinstance(self.line_count, bool):
            raise TypeError("Glasshouse mission render line count must be an integer")
        if self.line_count <= 0:
            raise ValueError("Glasshouse mission render line count must be positive")


def render_glasshouse_mission(
    surface: pygame.Surface,
    font: BitmapFont,
    presentation: GlasshouseMissionPresentation,
    camera: Camera,
    *,
    scale: int = 1,
    palette: GlasshouseMissionPalette = DEFAULT_GLASSHOUSE_MISSION_PALETTE,
) -> GlasshouseMissionRenderResult:
    """Render copied mission data without accessing authority state or commands."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("Glasshouse mission rendering requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("Glasshouse mission rendering requires a bitmap font")
    if not isinstance(presentation, GlasshouseMissionPresentation):
        raise TypeError("Glasshouse mission rendering requires mission presentation")
    if not isinstance(camera, Camera):
        raise TypeError("Glasshouse mission rendering requires a camera")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("Glasshouse mission render scale must be positive")
    if not isinstance(palette, GlasshouseMissionPalette):
        raise TypeError("Glasshouse mission render palette is invalid")
    render_tactical_view(
        surface,
        presentation.snapshot,
        camera,
    )
    lines = _status_lines(presentation, palette)
    line_height = font.measure("M", scale)[1]
    panel_height = len(lines) * line_height + 8
    pygame.draw.rect(surface, palette.panel, (4, 4, surface.get_width() - 8, panel_height))
    pygame.draw.rect(
        surface, palette.border, (4, 4, surface.get_width() - 8, panel_height), width=1
    )
    for index, (text, color) in enumerate(lines):
        surface.blit(font.render(text, color, scale), (8, 8 + index * line_height))
    return GlasshouseMissionRenderResult(len(lines))


def _status_lines(
    presentation: GlasshouseMissionPresentation,
    palette: GlasshouseMissionPalette,
) -> tuple[tuple[str, tuple[int, int, int]], ...]:
    lines = presentation.panel_lines
    return (
        (lines[0], palette.heading),
        (lines[1], palette.normal),
        (lines[2], palette.warning),
        (lines[3], palette.signal),
    )
