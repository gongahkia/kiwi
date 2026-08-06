"""Non-authoritative world-to-logical-canvas camera transforms."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from math import isfinite

from kiwi.sim.snapshot import PresentationPoint, PresentationRectangle


class Projection(StrEnum):
    """The renderer-only projection modes supported by the tactical camera."""

    TOP_DOWN = "top_down"
    ISOMETRIC = "isometric"


@dataclass(frozen=True, slots=True)
class Camera:
    """A display-only tactical camera centred in millimetres."""

    centre_x: float = 0.0
    centre_y: float = 0.0
    pixels_per_millimetre: float = 0.05
    projection: Projection = Projection.TOP_DOWN
    rotation_quarters: int = 0
    elevation_pixels: int = 8

    def __post_init__(self) -> None:
        values = (self.centre_x, self.centre_y, self.pixels_per_millimetre)
        if any(not isinstance(value, (int, float)) or isinstance(value, bool) for value in values):
            raise ValueError("camera values must be real numbers")
        if not all(isfinite(value) for value in values):
            raise ValueError("camera values must be finite")
        if self.pixels_per_millimetre <= 0:
            raise ValueError("camera scale must be positive")
        if not isinstance(self.projection, Projection):
            raise TypeError("camera projection is invalid")
        if not isinstance(self.rotation_quarters, int) or isinstance(self.rotation_quarters, bool):
            raise TypeError("camera rotation must be an integer")
        if not 0 <= self.rotation_quarters <= 3:
            raise ValueError("camera rotation must be between zero and three quarters")
        if not isinstance(self.elevation_pixels, int) or isinstance(self.elevation_pixels, bool):
            raise TypeError("camera elevation scale must be an integer")
        if self.elevation_pixels < 0:
            raise ValueError("camera elevation scale must be non-negative")


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
    relative_x, relative_y = _rotate(point.x - camera.centre_x, point.y - camera.centre_y, camera)
    if camera.projection is Projection.TOP_DOWN:
        return (
            round(width / 2 + relative_x * camera.pixels_per_millimetre),
            round(height / 2 - relative_y * camera.pixels_per_millimetre),
        )
    return (
        round(width / 2 + (relative_x - relative_y) * camera.pixels_per_millimetre),
        round(
            height / 2
            + (relative_x + relative_y) * camera.pixels_per_millimetre / 2
            - point.elevation * camera.elevation_pixels
        ),
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
    points = rectangle_polygon_to_canvas(rectangle, canvas_size, camera)
    minimum_x = min(point[0] for point in points)
    maximum_x = max(point[0] for point in points)
    minimum_y = min(point[1] for point in points)
    maximum_y = max(point[1] for point in points)
    return (minimum_x, minimum_y, max(1, maximum_x - minimum_x), max(1, maximum_y - minimum_y))


def rectangle_polygon_to_canvas(
    rectangle: PresentationRectangle,
    canvas_size: tuple[int, int],
    camera: Camera,
) -> tuple[tuple[int, int], tuple[int, int], tuple[int, int], tuple[int, int]]:
    """Project a rectangle as a stable clockwise tactical polygon."""
    if not isinstance(rectangle, PresentationRectangle):
        raise TypeError("camera projection requires a presentation rectangle")
    _canvas_size(canvas_size)
    if not isinstance(camera, Camera):
        raise TypeError("camera projection requires a camera")
    return tuple(
        world_to_canvas(point, canvas_size, camera)
        for point in (
            PresentationPoint(rectangle.minimum_x, rectangle.minimum_y, 0),
            PresentationPoint(rectangle.maximum_x, rectangle.minimum_y, 0),
            PresentationPoint(rectangle.maximum_x, rectangle.maximum_y, 0),
            PresentationPoint(rectangle.minimum_x, rectangle.maximum_y, 0),
        )
    )  # type: ignore[return-value]


def radius_to_canvas(radius: float, camera: Camera) -> int:
    """Project one non-negative display-world radius without authority conversion."""
    if not isinstance(radius, float) or not isfinite(radius) or radius < 0:
        raise ValueError("display radius must be a finite non-negative float")
    if not isinstance(camera, Camera):
        raise TypeError("camera projection requires a camera")
    return round(radius * camera.pixels_per_millimetre)


def isometric_depth_key(
    point: PresentationPoint, stable_id: int, camera: Camera
) -> tuple[float, int]:
    """Return the canonical display order for one isometric presentation item."""
    if not isinstance(point, PresentationPoint):
        raise TypeError("isometric depth requires a presentation point")
    if not isinstance(stable_id, int) or isinstance(stable_id, bool) or stable_id < 0:
        raise ValueError("isometric depth stable ID must be non-negative")
    if not isinstance(camera, Camera):
        raise TypeError("isometric depth requires a camera")
    rotated_x, rotated_y = _rotate(point.x - camera.centre_x, point.y - camera.centre_y, camera)
    return (rotated_x + rotated_y + point.elevation * 0.001, stable_id)


def _rotate(x: float, y: float, camera: Camera) -> tuple[float, float]:
    return ((x, y), (y, -x), (-x, -y), (-y, x))[camera.rotation_quarters]


def _canvas_size(value: tuple[int, int]) -> tuple[int, int]:
    if not isinstance(value, tuple) or len(value) != 2:
        raise ValueError("canvas size must be a two-item tuple")
    width, height = value
    if any(not isinstance(component, int) or isinstance(component, bool) for component in value):
        raise ValueError("canvas dimensions must be integers")
    if width <= 0 or height <= 0:
        raise ValueError("canvas dimensions must be positive")
    return width, height
