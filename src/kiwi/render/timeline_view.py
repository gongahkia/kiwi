"""Bitmap rendering for immutable retained mission timeline entries."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.ui.timeline import MissionTimeline


def _color(color: tuple[int, int, int]) -> None:
    if (
        not isinstance(color, tuple)
        or len(color) != 3
        or any(
            not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 255
            for value in color
        )
    ):
        raise ValueError("timeline colour must be an RGB tuple")


@dataclass(frozen=True, slots=True)
class TimelinePalette:
    normal: tuple[int, int, int] = (206, 221, 231)
    selected: tuple[int, int, int] = (245, 189, 74)

    def __post_init__(self) -> None:
        _color(self.normal)
        _color(self.selected)


DEFAULT_TIMELINE_PALETTE = TimelinePalette()


def render_mission_timeline(
    surface: pygame.Surface,
    font: BitmapFont,
    timeline: MissionTimeline,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: TimelinePalette = DEFAULT_TIMELINE_PALETTE,
) -> int:
    if not isinstance(surface, pygame.Surface) or not isinstance(font, BitmapFont):
        raise TypeError("timeline rendering requires a pygame surface and bitmap font")
    if not isinstance(timeline, MissionTimeline):
        raise TypeError("timeline rendering requires a mission timeline")
    if (
        not isinstance(origin, tuple)
        or len(origin) != 2
        or any(not isinstance(value, int) or isinstance(value, bool) for value in origin)
    ):
        raise TypeError("timeline rendering origin must be an integer pair")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("timeline rendering scale must be positive")
    if not isinstance(palette, TimelinePalette):
        raise TypeError("timeline rendering requires a timeline palette")
    line_height = font.measure("M", scale)[1]
    for index, entry in enumerate(timeline.entries):
        selected = entry.node_id == timeline.selected_node_id
        text = f"{'> ' if selected else '  '}t{entry.tick} {entry.kind.value}: {entry.summary}"
        surface.blit(
            font.render(text, palette.selected if selected else palette.normal, scale),
            (origin[0], origin[1] + index * line_height),
        )
    return len(timeline.entries) * line_height
