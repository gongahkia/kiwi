from __future__ import annotations

import os
import subprocess
import sys


def test_compile_output_panel_renders_a_successful_workbench_compilation() -> None:
    source = """
import pygame

from kiwi.dsl.source import SourceFileId
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.compile_output_view import (
    DEFAULT_COMPILE_OUTPUT_PALETTE,
    render_compile_output_panel,
)
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.ui.compile_output import compile_editor_source
from kiwi.ui.editor import EditorState

font = load_bitmap_font()
canvas = pygame.Surface((480, 96))
canvas.fill((0, 0, 0))
output = compile_editor_source(
    SourceFileId("workbench.dtr"), EditorState.from_text("fn choose(value: Int) -> Int = value")
)
result = render_compile_output_panel(canvas, font, output, (0, 0))
pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(96)}

assert result.line_count == 5
assert result.height == 5 * font.measure("M")[1]
assert DEFAULT_COMPILE_OUTPUT_PALETTE.success in pixels
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
