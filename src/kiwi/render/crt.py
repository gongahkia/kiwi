"""Cached presentation-only CRT compositing for pygame surfaces."""

from __future__ import annotations

import pygame


class CrtCompositor:
    """Apply scanlines, vignette, curvature framing, and restrained phosphor noise."""

    def __init__(self) -> None:
        self._overlay_key: tuple[int, int, tuple[int, int, int], bool] | None = None
        self._overlay: pygame.Surface | None = None

    def apply(
        self,
        surface: pygame.Surface,
        tint: tuple[int, int, int],
        elapsed_milliseconds: int,
        *,
        enabled: bool,
        reduced_flicker: bool,
    ) -> None:
        """Composite bounded renderer-time effects without touching game state."""
        if not isinstance(surface, pygame.Surface):
            raise TypeError("CRT compositor requires a pygame surface")
        if not _color(tint):
            raise ValueError("CRT tint must be RGB")
        if not isinstance(elapsed_milliseconds, int) or elapsed_milliseconds < 0:
            raise ValueError("CRT elapsed time must be non-negative")
        if not isinstance(enabled, bool) or not isinstance(reduced_flicker, bool):
            raise TypeError("CRT flags must be boolean")
        if not enabled:
            return
        overlay = self._static_overlay(surface.get_size(), tint, reduced_flicker)
        surface.blit(overlay, (0, 0))
        if reduced_flicker:
            return
        width, height = surface.get_size()
        phase = elapsed_milliseconds // 90
        for index in range(5):
            x = (phase * 37 + index * 149) % max(1, width)
            y = (phase * 19 + index * 71) % max(1, height)
            surface.fill((*tint, 22), (x, y, 1, 1), special_flags=pygame.BLEND_RGBA_ADD)

    def _static_overlay(
        self,
        size: tuple[int, int],
        tint: tuple[int, int, int],
        reduced_flicker: bool,
    ) -> pygame.Surface:
        key = (*size, tint, reduced_flicker)
        if key == self._overlay_key and self._overlay is not None:
            return self._overlay
        width, height = size
        overlay = pygame.Surface(size, pygame.SRCALPHA)
        scan_alpha = 20 if reduced_flicker else 34
        for y in range(1, height, 3):
            pygame.draw.line(overlay, (0, 0, 0, scan_alpha), (0, y), (width, y))
        edge = max(3, min(width, height) // 22)
        pygame.draw.rect(overlay, (0, 0, 0, 52), (0, 0, width, edge))
        pygame.draw.rect(overlay, (0, 0, 0, 52), (0, height - edge, width, edge))
        pygame.draw.rect(overlay, (0, 0, 0, 44), (0, 0, edge, height))
        pygame.draw.rect(overlay, (0, 0, 0, 44), (width - edge, 0, edge, height))
        pygame.draw.arc(
            overlay, (*tint, 80), (-edge, -edge, width + edge * 2, height + edge * 2), 0, 6.283, 1
        )
        self._overlay_key = key
        self._overlay = overlay
        return overlay


def _color(value: tuple[int, int, int]) -> bool:
    return (
        isinstance(value, tuple)
        and len(value) == 3
        and all(
            isinstance(component, int) and not isinstance(component, bool) and 0 <= component <= 255
            for component in value
        )
    )
