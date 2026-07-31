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
    open_pygame_window,
    present,
    render_basic_map,
)
from kiwi.render.pygame_lifecycle import pygame_is_initialised, quit_pygame
from kiwi.sim.snapshot import PresentationMap, PresentationRectangle, PresentationSnapshot

window = open_pygame_window((160, 90), (160, 90))
snapshot = PresentationSnapshot(
    0,
    \"prepared\",
    PresentationMap(PresentationRectangle(-1_000.0, -500.0, 1_000.0, 500.0), ()),
    (),
)
render_basic_map(window.logical_canvas, snapshot, Camera(pixels_per_millimetre=0.05))
assert window.logical_canvas.get_at((80, 45))[:3] == MAP_FILL_COLOR
assert window.logical_canvas.get_at((0, 0))[:3] == BACKGROUND_COLOR
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
