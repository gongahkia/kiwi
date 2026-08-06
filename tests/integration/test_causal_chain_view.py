from __future__ import annotations

import os
import subprocess
import sys


def test_causal_chain_panel_renders_selected_event_and_retained_links() -> None:
    source = """
import pygame

from kiwi.domain.ids import EntityId, EventId, TraceNodeId
from kiwi.render.bitmap_font import load_bitmap_font
from kiwi.render.causal_chain_view import (
    DEFAULT_CAUSAL_CHAIN_PALETTE,
    render_causal_chain_panel,
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
from kiwi.ui.causal_chain import CausalChainPanel, causal_chain_panel

trace = CausalTrace(
    b"c" * 32,
    TraceLevel.SUMMARY,
    (
        WorldEventTrace(TraceNodeId(1), 2, EventId(1), EventKind.FIRE_FIRED, "weapon fired"),
        ConsequenceTrace(
            TraceNodeId(2),
            2,
            TraceConsequenceKind.INJURY,
            (EntityId(1),),
            EventId(1),
            "operative injured",
        ),
    ),
    (
        TraceEdge(
            TraceEdgeId(1), TraceNodeId(1), TraceNodeId(2), TraceEdgeKind.CONTRIBUTED_TO
        ),
    ),
)
panel = causal_chain_panel(trace, TraceNodeId(2))
assert isinstance(panel, CausalChainPanel)
font = load_bitmap_font()
canvas = pygame.Surface((640, 200))
canvas.fill((0, 0, 0))
result = render_causal_chain_panel(canvas, font, panel, (0, 0))
pixels = {canvas.get_at((x, y))[:3] for x in range(640) for y in range(200)}

assert result.line_count == 10
assert DEFAULT_CAUSAL_CHAIN_PALETTE.selected in pixels
assert DEFAULT_CAUSAL_CHAIN_PALETTE.link in pixels
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
