"""Minimal pygame-ce window, logical canvas, and map-bounds renderer."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.camera import Camera, radius_to_canvas, rectangle_to_canvas, world_to_canvas
from kiwi.render.pygame_lifecycle import initialise_pygame
from kiwi.sim.snapshot import PresentationSnapshot

DEFAULT_WINDOW_SIZE = (960, 540)
DEFAULT_LOGICAL_CANVAS_SIZE = (480, 270)
WINDOW_TITLE = "Kiwi"
BACKGROUND_COLOR = (10, 14, 19)
MAP_FILL_COLOR = (25, 42, 48)
MAP_BORDER_COLOR = (88, 150, 144)
OBSTACLE_COLOR = (53, 69, 75)
PATH_COLOR = (245, 189, 74)
OPERATIVE_COLOR = (111, 216, 168)
OBJECTIVE_COLOR = (239, 99, 99)
VISIBILITY_RANGE_COLOR = (68, 119, 142)
VISIBLE_GEOMETRY_COLOR = (111, 174, 196)
CONTACT_UNCERTAINTY_COLOR = (230, 145, 102)
CONTACT_MARKER_COLOR = (255, 214, 130)
OPERATIVE_RADIUS_PIXELS = 4
OBJECTIVE_RADIUS_PIXELS = 6
CONTACT_RADIUS_PIXELS = 2


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


def render_tactical_view(
    logical_canvas: pygame.Surface,
    snapshot: PresentationSnapshot,
    camera: Camera,
) -> None:
    """Render copied map, obstacles, paths, operatives, and an optional marker."""
    render_basic_map(logical_canvas, snapshot, camera)
    if snapshot.map_geometry is not None:
        for map_obstacle in snapshot.map_geometry.obstacles:
            pygame.draw.rect(
                logical_canvas,
                OBSTACLE_COLOR,
                rectangle_to_canvas(map_obstacle.bounds, logical_canvas.get_size(), camera),
            )
    for overlay in snapshot.visibility_overlays:
        observer = world_to_canvas(overlay.observer, logical_canvas.get_size(), camera)
        radius = radius_to_canvas(overlay.sensor_radius, camera)
        if radius > 0:
            pygame.draw.circle(logical_canvas, VISIBILITY_RANGE_COLOR, observer, radius, width=1)
        for visible_obstacle in overlay.visible_obstacles:
            pygame.draw.rect(
                logical_canvas,
                VISIBLE_GEOMETRY_COLOR,
                rectangle_to_canvas(visible_obstacle.bounds, logical_canvas.get_size(), camera),
                width=1,
            )
    for contact in snapshot.contacts:
        estimated_position = world_to_canvas(
            contact.estimated_position,
            logical_canvas.get_size(),
            camera,
        )
        uncertainty_radius = radius_to_canvas(contact.uncertainty_radius, camera)
        if uncertainty_radius > 0:
            pygame.draw.circle(
                logical_canvas,
                CONTACT_UNCERTAINTY_COLOR,
                estimated_position,
                max(1, uncertainty_radius),
                width=1,
            )
        pygame.draw.circle(
            logical_canvas,
            CONTACT_MARKER_COLOR,
            estimated_position,
            CONTACT_RADIUS_PIXELS,
        )
    for operative in snapshot.operatives:
        if len(operative.path) > 1:
            pygame.draw.lines(
                logical_canvas,
                PATH_COLOR,
                False,
                tuple(
                    world_to_canvas(point, logical_canvas.get_size(), camera)
                    for point in operative.path
                ),
                width=1,
            )
    if snapshot.objective_marker is not None:
        pygame.draw.circle(
            logical_canvas,
            OBJECTIVE_COLOR,
            world_to_canvas(snapshot.objective_marker, logical_canvas.get_size(), camera),
            OBJECTIVE_RADIUS_PIXELS,
            width=1,
        )
    for operative in snapshot.operatives:
        pygame.draw.circle(
            logical_canvas,
            OPERATIVE_COLOR,
            world_to_canvas(operative.position, logical_canvas.get_size(), camera),
            OPERATIVE_RADIUS_PIXELS,
        )


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
