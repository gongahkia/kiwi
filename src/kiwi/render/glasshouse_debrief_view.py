"""Bitmap rendering of a selected Glasshouse injury consequence."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.render.causal_chain_view import (
    DEFAULT_CAUSAL_CHAIN_PALETTE,
    CausalChainPalette,
    render_causal_chain_panel,
)
from kiwi.ui.glasshouse_debrief import GlasshouseDebrief


def _color(color: tuple[int, int, int]) -> None:
    if (
        not isinstance(color, tuple)
        or len(color) != 3
        or any(
            not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 255
            for value in color
        )
    ):
        raise ValueError("Glasshouse debrief colour must be an RGB tuple")


@dataclass(frozen=True, slots=True)
class GlasshouseDebriefPalette:
    heading: tuple[int, int, int] = (111, 216, 238)
    normal: tuple[int, int, int] = (206, 221, 231)
    selected: tuple[int, int, int] = (245, 189, 74)

    def __post_init__(self) -> None:
        _color(self.heading)
        _color(self.normal)
        _color(self.selected)


DEFAULT_GLASSHOUSE_DEBRIEF_PALETTE = GlasshouseDebriefPalette()


@dataclass(frozen=True, slots=True)
class GlasshouseDebriefRenderResult:
    line_count: int

    def __post_init__(self) -> None:
        if (
            not isinstance(self.line_count, int)
            or isinstance(self.line_count, bool)
            or self.line_count < 1
        ):
            raise ValueError("Glasshouse debrief render result requires a positive line count")


def render_glasshouse_debrief(
    surface: pygame.Surface,
    font: BitmapFont,
    debrief: GlasshouseDebrief,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: GlasshouseDebriefPalette = DEFAULT_GLASSHOUSE_DEBRIEF_PALETTE,
    chain_palette: CausalChainPalette = DEFAULT_CAUSAL_CHAIN_PALETTE,
) -> GlasshouseDebriefRenderResult:
    """Render selected injury rows and its retained causal explanation."""
    if not isinstance(surface, pygame.Surface) or not isinstance(font, BitmapFont):
        raise TypeError("Glasshouse debrief rendering requires a pygame surface and bitmap font")
    if not isinstance(debrief, GlasshouseDebrief):
        raise TypeError("Glasshouse debrief rendering requires debrief state")
    if (
        not isinstance(origin, tuple)
        or len(origin) != 2
        or any(not isinstance(value, int) or isinstance(value, bool) for value in origin)
    ):
        raise TypeError("Glasshouse debrief rendering origin must be an integer pair")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("Glasshouse debrief render scale must be positive")
    if not isinstance(palette, GlasshouseDebriefPalette):
        raise TypeError("Glasshouse debrief render palette is invalid")
    if not isinstance(chain_palette, CausalChainPalette):
        raise TypeError("Glasshouse debrief chain palette is invalid")
    line_height = font.measure("M", scale)[1]
    rows = (("GLASSHOUSE DEBRIEF", palette.heading),) + tuple(
        (
            f"{'>' if injury.node_id == debrief.selected_node_id else ' '} "
            f"t{injury.tick} {injury.summary}",
            palette.selected if injury.node_id == debrief.selected_node_id else palette.normal,
        )
        for injury in debrief.injuries
    )
    for index, (text, color) in enumerate(rows):
        surface.blit(font.render(text, color, scale), (origin[0], origin[1] + index * line_height))
    chain = render_causal_chain_panel(
        surface,
        font,
        debrief.chain,
        (origin[0], origin[1] + len(rows) * line_height + line_height),
        scale=scale,
        palette=chain_palette,
    )
    return GlasshouseDebriefRenderResult(len(rows) + chain.line_count)
