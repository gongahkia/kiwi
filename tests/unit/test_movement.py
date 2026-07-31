from __future__ import annotations

from dataclasses import replace
from typing import cast

import pytest

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import EntityId
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.movement import OPERATIVE_MOVE_SPEED_PER_TICK, progress_movement_actions
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.state import MissionState, MovementAction, add_entity, movement_action_position


def position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def map_geometry() -> MapGeometry:
    return MapGeometry(
        WorldRectangle(
            WorldSubunits(-5_000), WorldSubunits(-5_000), WorldSubunits(5_000), WorldSubunits(5_000)
        )
    )


def movement_state(waypoints: tuple[WorldPosition, ...]) -> tuple[MissionState, EntityId]:
    geometry = map_geometry()
    state, entity = add_entity(MissionState(map_geometry=geometry), waypoints[0])
    path = Path(PathQuery(geometry, waypoints[0], waypoints[-1]), waypoints)
    return replace(
        state, movement_actions=(MovementAction(entity.entity_id, path),)
    ), entity.entity_id


def test_movement_progresses_with_exact_dominant_axis_rounding() -> None:
    state, entity_id = movement_state((position(0, 0), position(250, 150)))

    after_first = progress_movement_actions(state)
    after_second = progress_movement_actions(after_first)
    after_third = progress_movement_actions(after_second)

    assert OPERATIVE_MOVE_SPEED_PER_TICK == 100
    assert after_first.entities[0].position == position(100, 60)
    assert after_first.movement_actions[0].segment_progress == 100
    assert after_second.entities[0].position == position(200, 120)
    assert after_second.movement_actions[0].segment_progress == 200
    assert after_third.entities[0].entity_id == entity_id
    assert after_third.entities[0].position == position(250, 150)
    assert after_third.movement_actions == ()


def test_movement_carries_progress_across_canonical_waypoints() -> None:
    state, _ = movement_state((position(0, 0), position(100, 0), position(100, 200)))

    after_first = progress_movement_actions(state)
    after_second = progress_movement_actions(after_first)
    after_third = progress_movement_actions(after_second)

    assert after_first.entities[0].position == position(100, 0)
    assert after_first.movement_actions[0].next_waypoint_index == 2
    assert after_first.movement_actions[0].segment_progress == 0
    assert after_second.entities[0].position == position(100, 100)
    assert after_third.entities[0].position == position(100, 200)
    assert after_third.movement_actions == ()


def test_active_reducer_tick_progresses_movement_before_advancing_clock() -> None:
    state, _ = movement_state((position(0, 0), position(250, 0)))

    result = reduce_one_tick(
        state,
        FixedTickClock(TickRate.HZ_30),
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
    )

    assert result.state.tick == 1
    assert result.state.entities[0].position == position(100, 0)
    assert result.state.movement_actions[0].segment_progress == 100


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: MovementAction(EntityId(1), cast(Path, object())),
            "path",
        ),
        (
            lambda: MovementAction(
                EntityId(1),
                Path(
                    PathQuery(map_geometry(), position(0, 0), position(100, 0)),
                    (position(0, 0), position(100, 0)),
                ),
                next_waypoint_index=2,
            ),
            "outside the path",
        ),
    ),
)
def test_movement_action_rejects_invalid_progress(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def test_mission_state_rejects_action_position_that_does_not_match_progress() -> None:
    state, _ = movement_state((position(0, 0), position(250, 0)))
    progressed_action = replace(state.movement_actions[0], segment_progress=100)

    with pytest.raises(ValueError, match="match the entity position"):
        replace(state, movement_actions=(progressed_action,))

    assert movement_action_position(progressed_action) == position(100, 0)
