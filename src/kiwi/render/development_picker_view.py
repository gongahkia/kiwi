"""Bitmap rendering for the development policy and fixture picker."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.ui.development_picker import DevelopmentPicker


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("development picker palette color must be a three-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in color):
        raise ValueError("development picker palette color components must be integers")
    if any(component < 0 or component > 255 for component in color):
        raise ValueError("development picker palette color components must be 0 through 255")


@dataclass(frozen=True, slots=True)
class DevelopmentPickerPalette:
    """Fixed terminal colours for development picker entries."""

    normal: tuple[int, int, int] = (206, 221, 231)
    selected: tuple[int, int, int] = (111, 216, 168)
    heading: tuple[int, int, int] = (111, 216, 238)

    def __post_init__(self) -> None:
        for color in (self.normal, self.selected, self.heading):
            _validate_color(color)


DEFAULT_DEVELOPMENT_PICKER_PALETTE = DevelopmentPickerPalette()


@dataclass(frozen=True, slots=True)
class DevelopmentPickerRenderResult:
    """The number and height of rendered picker rows."""

    line_count: int
    height: int


def render_development_picker(
    surface: pygame.Surface,
    font: BitmapFont,
    picker: DevelopmentPicker,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: DevelopmentPickerPalette = DEFAULT_DEVELOPMENT_PICKER_PALETTE,
) -> DevelopmentPickerRenderResult:
    """Render policy and fixture options in their existing canonical order."""
    if not isinstance(surface, pygame.Surface):
        raise TypeError("development picker rendering requires a pygame surface")
    if not isinstance(font, BitmapFont):
        raise TypeError("development picker rendering requires a bitmap font")
    if not isinstance(picker, DevelopmentPicker):
        raise TypeError("development picker rendering requires a picker")
    _validate_origin(origin)
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("development picker rendering scale must be a positive integer")
    if not isinstance(palette, DevelopmentPickerPalette):
        raise TypeError("development picker rendering palette must be a picker palette")
    rows = (
        (("policies", None),)
        + tuple((option.label, option) for option in picker.policies)
        + (("fixtures", None),)
        + tuple((option.label, option) for option in picker.fixtures)
    )
    line_height = font.measure("M", scale)[1]
    for index, (text, option) in enumerate(rows):
        if option is None:
            color = palette.heading
            prefix = ""
        else:
            selected = option.path in (picker.selected_policy, picker.selected_fixture)
            color = palette.selected if selected else palette.normal
            prefix = "> " if selected else "  "
        surface.blit(
            font.render(prefix + text, color, scale), (origin[0], origin[1] + index * line_height)
        )
    return DevelopmentPickerRenderResult(len(rows), len(rows) * line_height)


def _validate_origin(origin: tuple[int, int]) -> None:
    if not isinstance(origin, tuple) or len(origin) != 2:
        raise TypeError("development picker rendering origin must be a two-item tuple")
    if any(not isinstance(component, int) or isinstance(component, bool) for component in origin):
        raise TypeError("development picker rendering origin components must be integers")
