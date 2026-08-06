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


def test_source_view_renders_lexer_styles_through_the_bitmap_font() -> None:
    source = """
import pygame

from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.render.source_view import DEFAULT_SOURCE_PALETTE, render_source

font = load_bitmap_font()
canvas = pygame.Surface((480, 80))
canvas.fill((0, 0, 0))
source = SourceFile(
    SourceFileId("styled.dtr"),
    'fn choose(value: Int) -> Bool = if true then "yes" else 0 @',
)
result = render_source(canvas, font, source, (0, 0))
pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(80)}

assert result.line_count == 1
assert result.line_height == font.measure("M")[1]
assert result.width > 0
assert result.height == result.line_height
assert DEFAULT_SOURCE_PALETTE.keyword in pixels
assert DEFAULT_SOURCE_PALETTE.literal in pixels
assert DEFAULT_SOURCE_PALETTE.operator in pixels
assert DEFAULT_SOURCE_PALETTE.punctuation in pixels
assert DEFAULT_SOURCE_PALETTE.invalid in pixels
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
