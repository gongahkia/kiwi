from __future__ import annotations

import os
import subprocess
import sys


def test_mission_timeline_view_renders_chronological_selection() -> None:
    source = """
import pygame

from kiwi.domain.ids import EntityId, EventId, TraceNodeId
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.render.timeline_view import (
    DEFAULT_TIMELINE_PALETTE,
    render_mission_timeline,
)
from kiwi.sim.events import EventKind
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    TraceConsequenceKind,
    TraceLevel,
    WorldEventTrace,
)
from kiwi.ui.timeline import mission_timeline

font = load_bitmap_font()
canvas = pygame.Surface((360, 64))
canvas.fill((0, 0, 0))
trace = CausalTrace(
    b"t" * 32,
    TraceLevel.SUMMARY,
    (
        WorldEventTrace(
            TraceNodeId(1), 2, EventId(1), EventKind.FIRE_FIRED, "weapon fired"
        ),
        ConsequenceTrace(
            TraceNodeId(2),
            1,
            TraceConsequenceKind.INJURY,
            (EntityId(1),),
            EventId(1),
            "operative injured",
        ),
    ),
    (),
)
timeline = mission_timeline(trace).select(TraceNodeId(1))
height = render_mission_timeline(canvas, font, timeline, (0, 0))
pixels = {canvas.get_at((x, y))[:3] for x in range(360) for y in range(64)}

assert height == 2 * font.measure("M")[1]
assert DEFAULT_TIMELINE_PALETTE.selected in pixels
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
