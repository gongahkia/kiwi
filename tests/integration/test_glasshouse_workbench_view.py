from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def test_glasshouse_briefing_and_workbench_render_through_bitmap_presentation() -> None:
    source = """
from pathlib import Path

import pygame

from kiwi.app.glasshouse_players import GLASSHOUSE_PLAYER_LOADOUTS
from kiwi.app.glasshouse_workbench import build_glasshouse_workbench
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.glasshouse_workbench_view import (
    DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE,
    render_glasshouse_workbench,
)
from kiwi.render.pygame_lifecycle import quit_pygame

root = Path.cwd()
sources = tuple(
    SourceFile(
        SourceFileId(loadout.policy_file_id),
        (root / loadout.policy_file_id).read_text(encoding=\"utf-8\"),
    )
    for loadout in GLASSHOUSE_PLAYER_LOADOUTS
)
font = load_bitmap_font()
canvas = pygame.Surface((480, 270))
briefing = build_glasshouse_workbench(sources)
briefing_result = render_glasshouse_workbench(canvas, font, briefing)
briefing_pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(270)}
assert briefing_result.phase.value == \"briefing\"
assert DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE.heading in briefing_pixels
workbench = briefing.open_workbench().select_policy(\"scout\").compile_selected()
workbench_result = render_glasshouse_workbench(canvas, font, workbench)
workbench_pixels = {canvas.get_at((x, y))[:3] for x in range(480) for y in range(270)}
assert workbench_result.phase.value == \"workbench\"
assert DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE.selected in workbench_pixels
assert DEFAULT_GLASSHOUSE_WORKBENCH_PALETTE.border in workbench_pixels
quit_pygame()
"""
    environment = dict(os.environ)
    environment["SDL_AUDIODRIVER"] = "dummy"
    environment["SDL_VIDEODRIVER"] = "dummy"

    result = subprocess.run(
        (sys.executable, "-c", source),
        check=False,
        capture_output=True,
        cwd=Path(__file__).resolve().parents[2],
        env=environment,
        text=True,
    )

    assert result.returncode == 0, result.stderr
