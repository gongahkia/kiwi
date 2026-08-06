from __future__ import annotations

import pytest

from kiwi.render.camera import Camera, radius_to_canvas, rectangle_to_canvas, world_to_canvas
from kiwi.sim.snapshot import PresentationPoint, PresentationRectangle


def test_camera_projects_world_coordinates_with_upward_positive_y() -> None:
    camera = Camera(centre_x=1_000.0, centre_y=2_000.0, pixels_per_millimetre=0.1)

    assert world_to_canvas(PresentationPoint(1_000.0, 2_000.0, 0), (480, 270), camera) == (240, 135)
    assert world_to_canvas(PresentationPoint(1_500.0, 1_500.0, 0), (480, 270), camera) == (290, 185)
    assert rectangle_to_canvas(
        PresentationRectangle(500.0, 1_500.0, 1_500.0, 2_500.0), (480, 270), camera
    ) == (190, 85, 100, 100)
    assert radius_to_canvas(125.0, camera) == 12


def test_camera_applies_renderer_only_screen_offsets_after_projection() -> None:
    camera = Camera(pixels_per_millimetre=0.1, screen_offset_x=3, screen_offset_y=-2)

    assert world_to_canvas(PresentationPoint(0.0, 0.0, 0), (480, 270), camera) == (243, 133)


@pytest.mark.parametrize(
    "factory",
    (
        lambda: Camera(pixels_per_millimetre=0.0),
        lambda: Camera(centre_x=float("nan")),
        lambda: world_to_canvas(PresentationPoint(0.0, 0.0, 0), (0, 270), Camera()),
        lambda: rectangle_to_canvas(object(), (480, 270), Camera()),  # type: ignore[arg-type]
        lambda: radius_to_canvas(-1.0, Camera()),
    ),
)
def test_camera_rejects_invalid_display_values(factory: object) -> None:
    with pytest.raises((TypeError, ValueError)):
        factory()  # type: ignore[operator]
