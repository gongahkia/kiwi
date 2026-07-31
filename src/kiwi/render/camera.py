"""Non-authoritative world-to-logical-canvas camera transforms."""

from __future__ import annotations

from dataclasses import dataclass
from math import isfinite

from kiwi.sim.snapshot import PresentationPoint, PresentationRectangle


@dataclass(frozen=True, slots=True)
class Camera:
    """A display-only top-down camera centred in millimetres."""

    centre_x: float = 0.0
    centre_y: float = 0.0
    pixels_per_millimetre: float = 0.05

    def __post_init__(self) -> None:
        values = (self.centre_x, self.centre_y, self.pixels_per_millimetre)
        if any(not isinstance(value, (int, float)) or isinstance(value, bool) for value in values):
            raise ValueError("camera values must be real numbers")
        if not all(isfinite(value) for value in values):
            raise ValueError("camera values must be finite")
        if self.pixels_per_millimetre <= 0:
            raise ValueError("camera scale must be positive")


def world_to_canvas(
    point: PresentationPoint,
    canvas_size: tuple[int, int],
    camera: Camera,
) -> tuple[int, int]:
    """Project one display-world point to integer logical-canvas coordinates."""
    if not isinstance(point, PresentationPoint):
        raise TypeError("camera projection requires a presentation point")
    width, height = _canvas_size(canvas_size)
    if not isinstance(camera, Camera):
        raise TypeError("camera projection requires a camera")
    return (
        round(width / 2 + (point.x - camera.centre_x) * camera.pixels_per_millimetre),
        round(height / 2 - (point.y - camera.centre_y) * camera.pixels_per_millimetre),
    )


def rectangle_to_canvas(
    rectangle: PresentationRectangle,
    canvas_size: tuple[int, int],
    camera: Camera,
) -> tuple[int, int, int, int]:
    """Project one display-world rectangle to a positive logical-canvas rectangle."""
    if not isinstance(rectangle, PresentationRectangle):
        raise TypeError("camera projection requires a presentation rectangle")
    _canvas_size(canvas_size)
    if not isinstance(camera, Camera):
        raise TypeError("camera projection requires a camera")
    left, top = world_to_canvas(
        PresentationPoint(rectangle.minimum_x, rectangle.maximum_y, 0), canvas_size, camera
    )
    right, bottom = world_to_canvas(
        PresentationPoint(rectangle.maximum_x, rectangle.minimum_y, 0), canvas_size, camera
    )
    return (left, top, max(1, right - left), max(1, bottom - top))


def radius_to_canvas(radius: float, camera: Camera) -> int:
    """Project one non-negative display-world radius without authority conversion."""
    if not isinstance(radius, float) or not isfinite(radius) or radius < 0:
        raise ValueError("display radius must be a finite non-negative float")
    if not isinstance(camera, Camera):
        raise TypeError("camera projection requires a camera")
    return round(radius * camera.pixels_per_millimetre)


def _canvas_size(value: tuple[int, int]) -> tuple[int, int]:
    if not isinstance(value, tuple) or len(value) != 2:
        raise ValueError("canvas size must be a two-item tuple")
    width, height = value
    if any(not isinstance(component, int) or isinstance(component, bool) for component in value):
        raise ValueError("canvas dimensions must be integers")
    if width <= 0 or height <= 0:
        raise ValueError("canvas dimensions must be positive")
    return width, height
