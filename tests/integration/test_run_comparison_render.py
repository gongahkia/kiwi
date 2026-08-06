from __future__ import annotations

import os
import subprocess
import sys


def test_run_comparison_render_renders_compatible_summary() -> None:
    source = """
import pygame

from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.render.run_comparison_view import (
    DEFAULT_RUN_COMPARISON_PALETTE,
    render_run_comparison_view,
)
from kiwi.replay.compatibility import RunCompatibility
from kiwi.replay.comparison import PolicyExecutionComparison
from kiwi.trace.comparison import ConsequenceComparison
from kiwi.ui.run_comparison import RunComparisonView

comparison = RunComparisonView(
    RunCompatibility((), ()),
    PolicyExecutionComparison(None, None),
    ConsequenceComparison(()),
    None,
)
font = load_bitmap_font()
canvas = pygame.Surface((480, 96))
canvas.fill((0, 0, 0))
result = render_run_comparison_view(canvas, font, comparison, (0, 0))
pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(96)}

assert result.line_count == 5
assert DEFAULT_RUN_COMPARISON_PALETTE.heading in pixels
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
