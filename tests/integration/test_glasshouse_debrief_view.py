from __future__ import annotations

import os
import subprocess
import sys


def test_glasshouse_debrief_renders_selected_injury_and_causal_chain() -> None:
    source = """
import pygame

from kiwi.domain.ids import EntityId, EventId, TraceNodeId
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.glasshouse_debrief_view import (
    DEFAULT_GLASSHOUSE_DEBRIEF_PALETTE,
    render_glasshouse_debrief,
)
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.sim.events import EventKind
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    TraceConsequenceKind,
    TraceEdge,
    TraceEdgeId,
    TraceEdgeKind,
    TraceLevel,
    WorldEventTrace,
)
from kiwi.ui.glasshouse_debrief import GlasshouseDebrief, glasshouse_debrief

trace = CausalTrace(
    b\"d\" * 32,
    TraceLevel.SUMMARY,
    (
        WorldEventTrace(TraceNodeId(1), 2, EventId(1), EventKind.DAMAGE_APPLIED, \"damage\"),
        ConsequenceTrace(
            TraceNodeId(2), 2, TraceConsequenceKind.INJURY, (EntityId(1),), EventId(1), \"injury\"
        ),
    ),
    (TraceEdge(TraceEdgeId(1), TraceNodeId(1), TraceNodeId(2), TraceEdgeKind.CONTRIBUTED_TO),),
)
debrief = glasshouse_debrief(trace)
assert isinstance(debrief, GlasshouseDebrief)
font = load_bitmap_font()
canvas = pygame.Surface((640, 240))
canvas.fill((0, 0, 0))
result = render_glasshouse_debrief(canvas, font, debrief, (0, 0))
pixels = {canvas.get_at((x, y))[:3] for x in range(640) for y in range(240)}
assert result.line_count > 3
assert DEFAULT_GLASSHOUSE_DEBRIEF_PALETTE.heading in pixels
assert DEFAULT_GLASSHOUSE_DEBRIEF_PALETTE.selected in pixels
quit_pygame()
"""
    environment = dict(os.environ)
    environment["SDL_AUDIODRIVER"] = "dummy"
    environment["SDL_VIDEODRIVER"] = "dummy"
    result = subprocess.run(
        (sys.executable, "-c", source), check=False, capture_output=True, env=environment, text=True
    )
    assert result.returncode == 0, result.stderr
