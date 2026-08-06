from __future__ import annotations

import os
import subprocess
import sys


def test_settings_view_renders_readable_scale_summary() -> None:
    source = """
import pygame

from kiwi.app.settings import UiSettings
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.render.settings_view import DEFAULT_SETTINGS_PALETTE, render_ui_settings

font = load_bitmap_font()
canvas = pygame.Surface((360, 64))
canvas.fill((0, 0, 0))
result = render_ui_settings(canvas, font, UiSettings(2, 2), (0, 0))
pixels = {canvas.get_at((x, y))[:3] for x in range(360) for y in range(64)}

assert result.line_count == 3
assert DEFAULT_SETTINGS_PALETTE.heading in pixels
quit_pygame()
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
