from __future__ import annotations

import os
import subprocess
import sys


def test_dummy_sdl_window_renders_and_presents_map_bounds() -> None:
    source = """
from kiwi.render.camera import Camera
from kiwi.render.pygame_app import (
    BACKGROUND_COLOR,
    CONTACT_MARKER_COLOR,
    CONTACT_UNCERTAINTY_COLOR,
    COVER_HIGH_COLOR,
    COVER_SLOT_EMPTY_COLOR,
    COVER_SLOT_OCCUPIED_COLOR,
    COVER_THREAT_DIRECTION_COLOR,
    MAP_FILL_COLOR,
    OBJECTIVE_COLOR,
    OBSTACLE_COLOR,
    OPERATIVE_COLOR,
    PATH_COLOR,
    VISIBLE_GEOMETRY_COLOR,
    VISIBILITY_RANGE_COLOR,
    open_pygame_window,
    present,
    render_tactical_view,
)
from kiwi.render.pygame_lifecycle import pygame_is_initialised, quit_pygame
from kiwi.sim.snapshot import (
    PresentationMap,
    PresentationCover,
    PresentationCoverSlot,
    PresentationContact,
    PresentationObstacle,
    PresentationOperative,
    PresentationPoint,
    PresentationRectangle,
    PresentationSnapshot,
    PresentationVisibilityOverlay,
    PresentationVisibleObstacle,
)

window = open_pygame_window((160, 90), (160, 90))
snapshot = PresentationSnapshot(
    0,
    \"prepared\",
    PresentationMap(
        PresentationRectangle(-1_000.0, -500.0, 1_000.0, 500.0),
        (PresentationObstacle(1, PresentationRectangle(-600.0, -100.0, -400.0, 100.0), 0),),
    ),
    (
        PresentationOperative(
            1,
            PresentationPoint(400.0, 0.0, 0),
            (PresentationPoint(-800.0, -200.0, 0), PresentationPoint(400.0, -200.0, 0)),
        ),
    ),
    PresentationPoint(0.0, 300.0, 0),
    (PresentationContact(1, 1, PresentationPoint(200.0, 200.0, 0), 200.0, 8_000, 1),),
    (
        PresentationVisibilityOverlay(
            1,
            PresentationPoint(0.0, 0.0, 0),
            300.0,
            (PresentationVisibleObstacle(1, PresentationRectangle(-600.0, -100.0, -400.0, 100.0)),),
        ),
    ),
    (
        PresentationCover(
            1,
            PresentationPoint(-200.0, 100.0, 0),
            PresentationPoint(200.0, 100.0, 0),
            "high",
            10_000,
            (
                PresentationCoverSlot(0, PresentationPoint(400.0, 0.0, 0), "left", 1),
                PresentationCoverSlot(1, PresentationPoint(-100.0, 200.0, 0), "right"),
            ),
        ),
    ),
)
render_tactical_view(window.logical_canvas, snapshot, Camera(pixels_per_millimetre=0.05))
assert window.logical_canvas.get_at((80, 45))[:3] == MAP_FILL_COLOR
assert window.logical_canvas.get_at((0, 0))[:3] == BACKGROUND_COLOR
assert window.logical_canvas.get_at((50, 45))[:3] == VISIBLE_GEOMETRY_COLOR
assert window.logical_canvas.get_at((60, 55))[:3] == PATH_COLOR
assert window.logical_canvas.get_at((100, 45))[:3] == OPERATIVE_COLOR
assert window.logical_canvas.get_at((80, 24))[:3] == OBJECTIVE_COLOR
assert window.logical_canvas.get_at((80, 30))[:3] == VISIBILITY_RANGE_COLOR
assert window.logical_canvas.get_at((99, 35))[:3] == CONTACT_UNCERTAINTY_COLOR
assert window.logical_canvas.get_at((90, 35))[:3] == CONTACT_MARKER_COLOR
assert window.logical_canvas.get_at((72, 40))[:3] == COVER_HIGH_COLOR
assert window.logical_canvas.get_at((85, 38))[:3] == COVER_THREAT_DIRECTION_COLOR
assert window.logical_canvas.get_at((78, 35))[:3] == COVER_SLOT_EMPTY_COLOR
assert window.logical_canvas.get_at((106, 45))[:3] == COVER_SLOT_OCCUPIED_COLOR
present(window)
assert pygame_is_initialised()
quit_pygame()
assert not pygame_is_initialised()
"""
    environment = dict(os.environ)
    environment["SDL_AUDIODRIVER"] = "dummy"
    environment["SDL_VIDEODRIVER"] = "dummy"

    result = subprocess.run(
        (sys.executable, "-c", source),
        check=False,
        capture_output=True,
        env=environment,
        text=True,
    )

    assert result.returncode == 0, result.stderr
