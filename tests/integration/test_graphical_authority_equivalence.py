from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import replace

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.events import CanonicalEvent, event_kind
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.runner import run_headless
from kiwi.sim.state import MissionPhase, MissionState, MovementAction, add_entity


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def _initial_state() -> MissionState:
    geometry = MapGeometry(
        WorldRectangle(
            WorldSubunits(-5_000),
            WorldSubunits(-5_000),
            WorldSubunits(5_000),
            WorldSubunits(5_000),
        )
    )
    state, entity = add_entity(
        MissionState(phase=MissionPhase.ACTIVE, map_geometry=geometry), _position(-1_000, 0)
    )
    path = Path(
        PathQuery(geometry, entity.position, _position(1_000, 0)),
        (entity.position, _position(1_000, 0)),
    )
    return replace(state, movement_actions=(MovementAction(entity.entity_id, path),))


def _event_summary(events: tuple[CanonicalEvent, ...]) -> list[dict[str, int | str]]:
    return [
        {
            "event_id": event.header.event_id.value,
            "kind": event_kind(event).value,
            "tick": event.header.tick,
        }
        for event in events
    ]


def test_dummy_sdl_presentation_does_not_change_authority_hash_or_events() -> None:
    headless = run_headless(_initial_state(), FixedTickClock(TickRate.HZ_30), 3)
    source = """
from dataclasses import replace
import json

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.render.camera import Camera
from kiwi.render.pygame_app import open_pygame_window, present, render_tactical_view
from kiwi.render.pygame_lifecycle import quit_pygame
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.events import event_kind
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.snapshot import build_presentation_snapshot
from kiwi.sim.state import MissionPhase, MissionState, MovementAction, add_entity

def position(x, y):
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))

geometry = MapGeometry(
    WorldRectangle(
        WorldSubunits(-5_000),
        WorldSubunits(-5_000),
        WorldSubunits(5_000),
        WorldSubunits(5_000),
    )
)
state, entity = add_entity(
    MissionState(phase=MissionPhase.ACTIVE, map_geometry=geometry),
    position(-1_000, 0),
)
path = Path(
    PathQuery(geometry, entity.position, position(1_000, 0)),
    (entity.position, position(1_000, 0)),
)
state = replace(state, movement_actions=(MovementAction(entity.entity_id, path),))
clock = FixedTickClock(TickRate.HZ_30)
window = open_pygame_window((160, 90), (160, 90))
events = []
for _ in range(3):
    render_tactical_view(window.logical_canvas, build_presentation_snapshot(state), Camera())
    present(window)
    result = reduce_one_tick(state, clock)
    state = result.state
    events.extend(result.events)
print(json.dumps({
    "events": [
        {
            "event_id": event.header.event_id.value,
            "kind": event_kind(event).value,
            "tick": event.header.tick,
        }
        for event in events
    ],
    "hash": hash_canonical_state(state).hex,
}, sort_keys=True))
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
    graphical = json.loads(result.stdout.splitlines()[-1])
    assert graphical == {
        "events": _event_summary(headless.events),
        "hash": hash_canonical_state(headless.state).hex,
    }
