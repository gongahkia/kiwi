from __future__ import annotations

import os
import subprocess
import sys


def test_terminal_tutorial_view_renders_one_selected_lesson_under_dummy_sdl() -> None:
    source = """
import pygame

from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.terminal_tutorial_view import (
    DEFAULT_TERMINAL_TUTORIAL_PALETTE,
    render_terminal_tutorial,
)
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.ui.terminal_tutorial import TERMINAL_LANGUAGE_TUTORIAL, TerminalTutorialConstruct

font = load_bitmap_font()
canvas = pygame.Surface((480, 270))
tutorial = TERMINAL_LANGUAGE_TUTORIAL.select_construct(TerminalTutorialConstruct.DISTANCE)
result = render_terminal_tutorial(canvas, font, tutorial)
pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(270)}
assert result.selected_lesson_index == 5
assert result.line_count == 8
assert DEFAULT_TERMINAL_TUTORIAL_PALETTE.heading in pixels
assert DEFAULT_TERMINAL_TUTORIAL_PALETTE.code in pixels
assert DEFAULT_TERMINAL_TUTORIAL_PALETTE.prompt in pixels
quit_pygame()
"""
    environment = dict(os.environ)
    environment["SDL_AUDIODRIVER"] = "dummy"
    environment["SDL_VIDEODRIVER"] = "dummy"

    result = subprocess.run(
        (sys.executable, "-c", source), check=False, capture_output=True, env=environment, text=True
    )

    assert result.returncode == 0, result.stderr
