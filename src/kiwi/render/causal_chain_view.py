"""Bitmap rendering for immutable event detail and causal-chain panels."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.bitmap_font import BitmapFont
from kiwi.ui.causal_chain import CausalChainPanel


def _color(color: tuple[int, int, int]) -> None:
    if (
        not isinstance(color, tuple)
        or len(color) != 3
        or any(
            not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 255
            for value in color
        )
    ):
        raise ValueError("causal chain colour must be an RGB tuple")


@dataclass(frozen=True, slots=True)
class CausalChainPalette:
    normal: tuple[int, int, int] = (206, 221, 231)
    heading: tuple[int, int, int] = (110, 177, 223)
    selected: tuple[int, int, int] = (245, 189, 74)
    link: tuple[int, int, int] = (139, 164, 178)

    def __post_init__(self) -> None:
        _color(self.normal)
        _color(self.heading)
        _color(self.selected)
        _color(self.link)


DEFAULT_CAUSAL_CHAIN_PALETTE = CausalChainPalette()


@dataclass(frozen=True, slots=True)
class CausalChainRenderResult:
    line_count: int
    height: int


def render_causal_chain_panel(
    surface: pygame.Surface,
    font: BitmapFont,
    panel: CausalChainPanel,
    origin: tuple[int, int],
    *,
    scale: int = 1,
    palette: CausalChainPalette = DEFAULT_CAUSAL_CHAIN_PALETTE,
) -> CausalChainRenderResult:
    """Draw one selected retained event and its causal ancestor graph."""
    if not isinstance(surface, pygame.Surface) or not isinstance(font, BitmapFont):
        raise TypeError("causal chain rendering requires a pygame surface and bitmap font")
    if not isinstance(panel, CausalChainPanel):
        raise TypeError("causal chain rendering requires a causal chain panel")
    if (
        not isinstance(origin, tuple)
        or len(origin) != 2
        or any(not isinstance(value, int) or isinstance(value, bool) for value in origin)
    ):
        raise TypeError("causal chain rendering origin must be an integer pair")
    if not isinstance(scale, int) or isinstance(scale, bool) or scale < 1:
        raise ValueError("causal chain rendering scale must be positive")
    if not isinstance(palette, CausalChainPalette):
        raise TypeError("causal chain rendering requires a causal chain palette")
    lines = _lines(panel, palette)
    line_height = font.measure("M", scale)[1]
    for index, (text, color) in enumerate(lines):
        surface.blit(font.render(text, color, scale), (origin[0], origin[1] + index * line_height))
    return CausalChainRenderResult(len(lines), len(lines) * line_height)


def _lines(
    panel: CausalChainPanel,
    palette: CausalChainPalette,
) -> tuple[tuple[str, tuple[int, int, int]], ...]:
    event = panel.detail.event
    rows: list[tuple[str, tuple[int, int, int]]] = [
        (f"t{event.tick} {event.kind.value}: {event.summary}", palette.selected)
    ]
    rows.extend((f"{field.label}: {field.value}", palette.normal) for field in panel.detail.fields)
    rows.append((f"parents: {len(panel.detail.parent_links)}", palette.normal))
    rows.append((f"children: {len(panel.detail.child_links)}", palette.normal))
    rows.append(("causal ancestors", palette.heading))
    if panel.ancestors:
        rows.extend(
            (
                f"  {ancestor.distance}. t{ancestor.node.tick} "
                f"{ancestor.node.kind.value}: {ancestor.node.summary}",
                palette.normal,
            )
            for ancestor in panel.ancestors
        )
    else:
        rows.append(("  no retained causal parents", palette.normal))
    rows.append(("causal links", palette.heading))
    if panel.links:
        rows.extend(
            (
                f"  n{link.source_node_id.value} -{link.kind.value}-> n{link.target_node_id.value}",
                palette.link,
            )
            for link in panel.links
        )
    else:
        rows.append(("  no retained causal links", palette.normal))
    return tuple(rows)
