from __future__ import annotations

from dataclasses import replace

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.sim.aim import AimProgression, resolve_aim_progression
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.movement import MovementBlockReason, MovementResolution, MovementResolutionKind
from kiwi.sim.observations import build_runtime_observations
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.state import MissionPhase, MissionState, MovementAction, add_entity
from kiwi.sim.weapons import AimState, AimStore, SuppressionState, SuppressionStore


def test_aim_reaches_full_quality_in_one_second_at_every_supported_tick_rate() -> None:
    for rate in TickRate:
        clock = FixedTickClock(rate)
        state, entity = add_entity(MissionState(), _position(0, 0))
        for _ in range(int(rate)):
            phase = resolve_aim_progression(state, clock, ())
            state = clock.advance(phase.state)
        assert state.aim_states.quality_for(entity.entity_id) == 10_000


def test_suppression_clamps_stationary_aim_and_reports_the_exact_modifier_breakdown() -> None:
    state, entity = add_entity(MissionState(), _position(0, 0))
    state = replace(
        state,
        aim_states=AimStore((AimState(entity.entity_id, 9_000),)),
        suppressions=SuppressionStore((SuppressionState(entity.entity_id, 3_000),)),
    )

    phase = resolve_aim_progression(state, FixedTickClock(TickRate.HZ_20), ())

    assert phase.state.aim_states.quality_for(entity.entity_id) == 7_000
    assert phase.progressions == (
        AimProgression(entity.entity_id, 9_000, 3_000, 7_000, 500, False, 7_000),
    )


def test_actual_movement_resets_aim_but_a_blocked_attempt_keeps_progressing() -> None:
    state, entity = add_entity(MissionState(), _position(0, 0))
    state = replace(state, aim_states=AimStore((AimState(entity.entity_id, 2_000),)))
    clock = FixedTickClock(TickRate.HZ_20)
    moved = _position(100, 0)
    actual_move = MovementResolution(
        state.tick,
        entity.entity_id,
        entity.position,
        moved,
        moved,
        MovementResolutionKind.PROGRESSED,
    )

    after_move = resolve_aim_progression(state, clock, (actual_move,)).state
    assert after_move.aim_states.quality_for(entity.entity_id) == 0

    blocked = MovementResolution(
        state.tick,
        entity.entity_id,
        entity.position,
        moved,
        entity.position,
        MovementResolutionKind.BLOCKED,
        MovementBlockReason.MAP_COLLISION,
    )
    after_block = resolve_aim_progression(state, clock, (blocked,)).state
    assert after_block.aim_states.quality_for(entity.entity_id) == 2_500


def test_reducer_resets_aim_after_resolved_movement_before_advancing_the_clock() -> None:
    geometry = MapGeometry(
        WorldRectangle(
            WorldSubunits(-5_000),
            WorldSubunits(-5_000),
            WorldSubunits(5_000),
            WorldSubunits(5_000),
        )
    )
    state, entity = add_entity(
        MissionState(phase=MissionPhase.ACTIVE, map_geometry=geometry), _position(0, 0)
    )
    goal = _position(300, 0)
    path = Path(PathQuery(geometry, entity.position, goal), (entity.position, goal))
    state = replace(
        state,
        movement_actions=(MovementAction(entity.entity_id, path),),
        aim_states=AimStore((AimState(entity.entity_id, 2_000),)),
    )

    result = reduce_one_tick(state, FixedTickClock(TickRate.HZ_30))

    assert result.state.tick == 1
    assert result.state.entities[0].position == _position(100, 0)
    assert result.state.aim_states.quality_for(entity.entity_id) == 0
    assert (
        build_runtime_observations(result.state)[0].self_observation.aim_quality_basis_points == 0
    )


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))
