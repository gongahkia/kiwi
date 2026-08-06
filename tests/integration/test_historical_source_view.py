from __future__ import annotations

import os
import subprocess
import sys


def test_historical_source_pane_renders_archive_bound_highlight() -> None:
    source = """
import pygame

from kiwi.domain.ids import EntityId
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.historical_source_view import (
    DEFAULT_HISTORICAL_SOURCE_PALETTE,
    render_historical_source_pane,
)
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.sim.policy_versions import PolicyVersion
from kiwi.ui.historical_source import HistoricalSourcePane

historical = SourceFile(SourceFileId("historical.dtr"), "fn choose(value: Int) -> Int = value")
span = historical.span(ByteOffset(3), ByteOffset(9))
pane = HistoricalSourcePane(
    EntityId(1),
    PolicyVersion(b"p" * 32),
    historical,
    ExpressionId(1),
    (span,),
)
font = load_bitmap_font()
canvas = pygame.Surface((480, 80))
canvas.fill((0, 0, 0))
result = render_historical_source_pane(canvas, font, pane, (0, 0))
pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(80)}

assert result.highlight_count == 1
assert result.height == 2 * font.measure("M")[1]
assert DEFAULT_HISTORICAL_SOURCE_PALETTE.highlight in pixels
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
