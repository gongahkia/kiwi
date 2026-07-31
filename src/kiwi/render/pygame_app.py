"""Minimal pygame-ce window, logical canvas, and map-bounds renderer."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.camera import Camera, rectangle_to_canvas
from kiwi.render.pygame_lifecycle import initialise_pygame
from kiwi.sim.snapshot import PresentationSnapshot

DEFAULT_WINDOW_SIZE = (960, 540)
DEFAULT_LOGICAL_CANVAS_SIZE = (480, 270)
WINDOW_TITLE = "Kiwi"
BACKGROUND_COLOR = (10, 14, 19)
MAP_FILL_COLOR = (25, 42, 48)
MAP_BORDER_COLOR = (88, 150, 144)


@dataclass(frozen=True, slots=True)
class PygameWindow:
    """One mutable pygame surface pair behind immutable display dimensions."""

    window: pygame.Surface
    logical_canvas: pygame.Surface
    logical_size: tuple[int, int]

    def __post_init__(self) -> None:
        if not isinstance(self.window, pygame.Surface):
            raise ValueError("pygame window requires a pygame surface")
        if not isinstance(self.logical_canvas, pygame.Surface):
            raise ValueError("logical canvas requires a pygame surface")
        if self.logical_canvas.get_size() != self.logical_size:
            raise ValueError("logical canvas size must match its surface")
        _size(self.logical_size, "logical canvas")


def open_pygame_window(
    window_size: tuple[int, int] = DEFAULT_WINDOW_SIZE,
    logical_size: tuple[int, int] = DEFAULT_LOGICAL_CANVAS_SIZE,
) -> PygameWindow:
    """Initialise pygame-ce and create a window with a separate logical canvas."""
    _size(window_size, "window")
    _size(logical_size, "logical canvas")
    initialise_pygame()
    pygame.display.set_caption(WINDOW_TITLE)
    return PygameWindow(
        window=pygame.display.set_mode(window_size),
        logical_canvas=pygame.Surface(logical_size),
        logical_size=logical_size,
    )


def render_basic_map(
    logical_canvas: pygame.Surface,
    snapshot: PresentationSnapshot,
    camera: Camera,
) -> None:
    """Draw the map bounds only; entities, obstacles, and overlays follow later."""
    if not isinstance(logical_canvas, pygame.Surface):
        raise TypeError("map rendering requires a pygame surface")
    if not isinstance(snapshot, PresentationSnapshot):
        raise TypeError("map rendering requires a presentation snapshot")
    if not isinstance(camera, Camera):
        raise TypeError("map rendering requires a camera")
    logical_canvas.fill(BACKGROUND_COLOR)
    if snapshot.map_geometry is None:
        return
    bounds = rectangle_to_canvas(snapshot.map_geometry.bounds, logical_canvas.get_size(), camera)
    pygame.draw.rect(logical_canvas, MAP_FILL_COLOR, bounds)
    pygame.draw.rect(logical_canvas, MAP_BORDER_COLOR, bounds, width=1)


def present(window: PygameWindow) -> None:
    """Scale the logical canvas into the current window and present one frame."""
    if not isinstance(window, PygameWindow):
        raise TypeError("presentation requires a pygame window")
    window_size = window.window.get_size()
    if window_size == window.logical_size:
        window.window.blit(window.logical_canvas, (0, 0))
    else:
        window.window.blit(pygame.transform.scale(window.logical_canvas, window_size), (0, 0))
    pygame.display.flip()


def _size(value: tuple[int, int], label: str) -> tuple[int, int]:
    if not isinstance(value, tuple) or len(value) != 2:
        raise ValueError(f"{label} size must be a two-item tuple")
    width, height = value
    if any(not isinstance(component, int) or isinstance(component, bool) for component in value):
        raise ValueError(f"{label} dimensions must be integers")
    if width <= 0 or height <= 0:
        raise ValueError(f"{label} dimensions must be positive")
    return width, height
