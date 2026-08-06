"""Bitmap rendering for non-authoritative readable-scale settings."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.app.settings import UiSettings
from kiwi.render.bitmap_font import BitmapFont


@dataclass(frozen=True, slots=True)
class SettingsPalette:
    heading: tuple[int, int, int] = (110, 177, 223)
    normal: tuple[int, int, int] = (206, 221, 231)


DEFAULT_SETTINGS_PALETTE = SettingsPalette()


@dataclass(frozen=True, slots=True)
class SettingsRenderResult:
    line_count: int
    height: int


def render_ui_settings(
    surface: pygame.Surface,
    font: BitmapFont,
    settings: UiSettings,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: SettingsPalette = DEFAULT_SETTINGS_PALETTE,
) -> SettingsRenderResult:
    """Render integer UI and font scaling values without mutating settings."""
    if not isinstance(surface, pygame.Surface) or not isinstance(font, BitmapFont):
        raise TypeError("settings rendering requires a pygame surface and bitmap font")
    if not isinstance(settings, UiSettings):
        raise TypeError("settings rendering requires UI settings")
    if (
        not isinstance(origin, tuple)
        or len(origin) != 2
        or any(not isinstance(value, int) or isinstance(value, bool) for value in origin)
    ):
        raise TypeError("settings rendering origin must be an integer pair")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("settings rendering scale must be positive")
    if not isinstance(palette, SettingsPalette):
        raise TypeError("settings rendering requires a settings palette")
    lines = (
        ("display settings", palette.heading),
        (f"UI scale: {settings.ui_scale}x", palette.normal),
        (
            f"font scale: {settings.font_scale}x ({settings.font_pixel_height}px effective)",
            palette.normal,
        ),
    )
    line_height = font.measure("M", scale)[1]
    for index, (text, color) in enumerate(lines):
        surface.blit(font.render(text, color, scale), (origin[0], origin[1] + index * line_height))
    return SettingsRenderResult(len(lines), len(lines) * line_height)
