from __future__ import annotations

from dataclasses import replace

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import IdAllocator
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.events import MovementArrived, MovementBlocked, MovementProgressed
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.movement import MovementBlockReason
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.state import MissionState, MovementAction, add_entity


def position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def rectangle(minimum_x: int, minimum_y: int, maximum_x: int, maximum_y: int) -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(minimum_x),
        WorldSubunits(minimum_y),
        WorldSubunits(maximum_x),
        WorldSubunits(maximum_y),
    )


def action_state(start: WorldPosition, goal: WorldPosition) -> MissionState:
    geometry = MapGeometry(rectangle(-2_000, -2_000, 2_000, 2_000))
    state, entity = add_entity(MissionState(map_geometry=geometry), start)
    path = Path(PathQuery(geometry, start, goal), (start, goal))
    return replace(state, movement_actions=(MovementAction(entity.entity_id, path),))


def test_reducer_emits_progress_and_arrival_events_in_movement_order() -> None:
    clock = FixedTickClock(TickRate.HZ_30)
    first = reduce_one_tick(
        action_state(position(0, 0), position(250, 0)),
        clock,
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
    )
    second = reduce_one_tick(first.state, clock)
    third = reduce_one_tick(second.state, clock)

    first_progress = tuple(event for event in first.events if isinstance(event, MovementProgressed))
    second_progress = tuple(
        event for event in second.events if isinstance(event, MovementProgressed)
    )
    arrivals = tuple(event for event in third.events if isinstance(event, MovementArrived))

    assert len(first_progress) == len(second_progress) == len(arrivals) == 1
    assert first_progress[0].resolution.start_position == position(0, 0)
    assert first_progress[0].resolution.result_position == position(100, 0)
    assert second_progress[0].resolution.result_position == position(200, 0)
    assert arrivals[0].resolution.result_position == position(250, 0)
    assert tuple(event.header.event_id.value for event in first.events) == (1, 2)


def test_reducer_emits_structured_block_events() -> None:
    obstacle_id, allocator = IdAllocator().allocate_obstacle()
    geometry = MapGeometry(
        rectangle(-2_000, -2_000, 2_000, 2_000),
        (MapObstacle(obstacle_id, rectangle(0, -10, 1, 10)),),
    )
    start = position(-500, 0)
    goal = position(500, 0)
    state, entity = add_entity(MissionState(map_geometry=geometry, id_allocator=allocator), start)
    state = replace(
        state,
        movement_actions=(
            MovementAction(entity.entity_id, Path(PathQuery(geometry, start, goal), (start, goal))),
        ),
    )
    clock = FixedTickClock(TickRate.HZ_30)
    first = reduce_one_tick(
        state,
        clock,
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
    )
    blocked = reduce_one_tick(first.state, clock)

    events = tuple(event for event in blocked.events if isinstance(event, MovementBlocked))

    assert len(events) == 1
    assert events[0].resolution.block_reason is MovementBlockReason.MAP_COLLISION
    assert events[0].resolution.start_position == position(-400, 0)
    assert events[0].resolution.attempted_position == position(-300, 0)
    assert events[0].resolution.result_position == position(-400, 0)
