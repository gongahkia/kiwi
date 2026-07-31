from __future__ import annotations

import os
import subprocess
import sys


def test_dummy_sdl_window_renders_and_presents_map_bounds() -> None:
    source = """
from kiwi.render.camera import Camera
from kiwi.render.pygame_app import (
    BACKGROUND_COLOR,
    MAP_FILL_COLOR,
    OBJECTIVE_COLOR,
    OBSTACLE_COLOR,
    OPERATIVE_COLOR,
    PATH_COLOR,
    open_pygame_window,
    present,
    render_tactical_view,
)
from kiwi.render.pygame_lifecycle import pygame_is_initialised, quit_pygame
from kiwi.sim.snapshot import (
    PresentationMap,
    PresentationObstacle,
    PresentationOperative,
    PresentationPoint,
    PresentationRectangle,
    PresentationSnapshot,
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
)
render_tactical_view(window.logical_canvas, snapshot, Camera(pixels_per_millimetre=0.05))
assert window.logical_canvas.get_at((80, 45))[:3] == MAP_FILL_COLOR
assert window.logical_canvas.get_at((0, 0))[:3] == BACKGROUND_COLOR
assert window.logical_canvas.get_at((50, 45))[:3] == OBSTACLE_COLOR
assert window.logical_canvas.get_at((60, 55))[:3] == PATH_COLOR
assert window.logical_canvas.get_at((100, 45))[:3] == OPERATIVE_COLOR
assert window.logical_canvas.get_at((80, 24))[:3] == OBJECTIVE_COLOR
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
