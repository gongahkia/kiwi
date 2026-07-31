from __future__ import annotations

import os
import subprocess
import sys


def test_bigblueterm_renders_two_colour_bitmap_and_scales_without_sampling() -> None:
    source = """
import pygame

from kiwi.render.bitmap_font import (
    BIGBLUETERM_FONT_PATH,
    BIGBLUETERM_NATIVE_PIXEL_HEIGHT,
    load_bitmap_font,
    scale_nearest_neighbour,
)
from kiwi.render.pygame_lifecycle import quit_pygame

font = load_bitmap_font()
assert font.source_path == BIGBLUETERM_FONT_PATH
assert font.pixel_height == BIGBLUETERM_NATIVE_PIXEL_HEIGHT == 12
glyph = font.render("K", (255, 0, 0), scale=3)
assert glyph.get_bitsize() == 8
assert glyph.get_width() > 0
assert glyph.get_height() > 0

source_surface = pygame.Surface((2, 2))
source_surface.set_at((0, 0), (255, 0, 0))
source_surface.set_at((1, 0), (0, 255, 0))
source_surface.set_at((0, 1), (0, 0, 255))
source_surface.set_at((1, 1), (255, 255, 255))
scaled = scale_nearest_neighbour(source_surface, 3)
assert scaled.get_size() == (6, 6)
assert scaled.get_at((2, 2))[:3] == (255, 0, 0)
assert scaled.get_at((3, 2))[:3] == (0, 255, 0)
assert scaled.get_at((2, 3))[:3] == (0, 0, 255)
assert scaled.get_at((3, 3))[:3] == (255, 255, 255)
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
