from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldSubunits, WorldVector
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.combat_events import emit_projectile_events, emit_suppression_events
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.events import ProjectileAdvanced, SuppressionChanged
from kiwi.sim.intentions import IntentionKind, IntentionOrigin
from kiwi.sim.projectile_impacts import resolve_projectile_impacts
from kiwi.sim.projectiles import Projectile, ProjectileProvenance, ProjectileStore
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.state import EntityState, MissionState, add_entity
from kiwi.sim.suppression import (
    IMPACT_SUPPRESSION_BASIS_POINTS,
    NEAR_MISS_SUPPRESSION_BASIS_POINTS,
    SUPPRESSION_DECAY_PER_TICK_BASIS_POINTS,
    SuppressionPhase,
    SuppressionResolution,
    SuppressionSourceKind,
    resolve_projectile_suppression,
)
from kiwi.sim.weapons import AimState, AimStore, SuppressionState, SuppressionStore


def test_path_suppresses_exact_two_metre_near_misses_but_not_owner_or_far_entities() -> None:
    state, entities = _state_with_entities(
        position(-1_000, 1_000),
        position(500, 2_000),
        position(500, 2_001),
        position(500, 0, elevation=1),
    )
    state = _with_projectile(state, entities[0])

    phase = resolve_projectile_suppression(state, state.projectiles.entries, ())

    owner, near_miss, beyond_range, upper_level = entities
    assert phase.state.suppressions.suppression_for(owner.entity_id) == 0
    assert phase.state.suppressions.suppression_for(near_miss.entity_id) == 1_500
    assert phase.state.suppressions.suppression_for(beyond_range.entity_id) == 0
    assert phase.state.suppressions.suppression_for(upper_level.entity_id) == 0
    near_resolution = _resolution_for(phase, near_miss)
    assert near_resolution.contributions[0].source_kind is SuppressionSourceKind.NEAR_MISS
    assert near_resolution.contributions[0].basis_points == NEAR_MISS_SUPPRESSION_BASIS_POINTS


def test_suppression_events_parent_current_tick_projectile_outcomes() -> None:
    state, entities = _state_with_entities(position(-1_000, 1_000), position(500, 2_000))
    state = _with_projectile(state, entities[0])
    impacts = resolve_projectile_impacts(state)
    projectile_events = emit_projectile_events(impacts)
    suppression = resolve_projectile_suppression(
        projectile_events.state,
        state.projectiles.entries,
        impacts.impacts,
    )

    emitted = emit_suppression_events(suppression, projectile_events.events)

    projectile_event = next(
        event for event in projectile_events.events if isinstance(event, ProjectileAdvanced)
    )
    changed = next(event for event in emitted.events if isinstance(event, SuppressionChanged))
    assert changed.header.parent_event_ids == (projectile_event.header.event_id,)
    assert changed.resolution.entity_id == entities[1].entity_id


def test_operative_impact_suppresses_three_metre_radius_without_a_direct_hit_near_miss() -> None:
    state, entities = _state_with_entities(
        position(-1_000, 1_000),
        position(850, 0),
        position(500, 3_000),
        position(500, 3_001),
    )
    state = _with_projectile(state, entities[0])
    impacts = resolve_projectile_impacts(state)

    phase = resolve_projectile_suppression(
        impacts.state,
        state.projectiles.entries,
        impacts.impacts,
    )

    owner, direct_target, impact_neighbour, beyond_range = entities
    assert phase.state.suppressions.suppression_for(owner.entity_id) == 0
    assert phase.state.suppressions.suppression_for(direct_target.entity_id) == 2_500
    assert phase.state.suppressions.suppression_for(impact_neighbour.entity_id) == 2_500
    assert phase.state.suppressions.suppression_for(beyond_range.entity_id) == 0
    direct_contributions = _resolution_for(phase, direct_target).contributions
    assert tuple(contribution.source_kind for contribution in direct_contributions) == (
        SuppressionSourceKind.IMPACT,
    )
    assert direct_contributions[0].basis_points == IMPACT_SUPPRESSION_BASIS_POINTS
    assert direct_contributions[0].impact == impacts.impacts[0]


def test_suppression_decays_before_new_contributions_cap_and_immediately_clamp_aim() -> None:
    state, entities = _state_with_entities(position(-1_000, 1_000), position(500, 2_000))
    state = _with_projectile(state, entities[0])
    state = _with_projectile(state, entities[0])
    target = entities[1]
    state = replace(
        state,
        suppressions=SuppressionStore((SuppressionState(target.entity_id, 8_500),)),
        aim_states=AimStore((AimState(target.entity_id, 9_000),)),
    )

    phase = resolve_projectile_suppression(state, state.projectiles.entries, ())

    resolution = _resolution_for(phase, target)
    assert SUPPRESSION_DECAY_PER_TICK_BASIS_POINTS == 500
    assert resolution.decay_basis_points == 500
    assert len(resolution.contributions) == 2
    assert tuple(contribution.basis_points for contribution in resolution.contributions) == (
        1_500,
        1_500,
    )
    assert resolution.suppression_after == 10_000
    assert resolution.aim_ceiling_after == 0
    assert phase.state.aim_states.quality_for(target.entity_id) == 0


def test_active_reducer_applies_projectile_path_suppression_before_clock_advance() -> None:
    state, entities = _state_with_entities(position(-1_000, 1_000), position(500, 2_000))
    state = _with_projectile(state, entities[0])
    target = entities[1]
    state = replace(state, aim_states=AimStore((AimState(target.entity_id, 9_000),)))

    result = reduce_one_tick(
        state,
        FixedTickClock(TickRate.HZ_30),
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
    )

    assert result.state.tick == 1
    assert result.state.suppressions.suppression_for(target.entity_id) == 1_500
    assert result.state.aim_states.quality_for(target.entity_id) == 8_500


def test_active_reducer_applies_impact_suppression_after_damage() -> None:
    state, entities = _state_with_entities(position(-1_000, 1_000), position(850, 0))
    state = _with_projectile(state, entities[0])
    target = entities[1]
    state = replace(state, aim_states=AimStore((AimState(target.entity_id, 9_000),)))

    result = reduce_one_tick(
        state,
        FixedTickClock(TickRate.HZ_30),
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
    )

    assert result.state.tick == 1
    assert result.state.conditions.condition_for(target.entity_id).protection == 0
    assert result.state.suppressions.suppression_for(target.entity_id) == 2_500
    assert result.state.aim_states.quality_for(target.entity_id) == 7_500


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: resolve_projectile_suppression(object(), (), ()), "mission state"),  # type: ignore[arg-type]
        (lambda: resolve_projectile_suppression(MissionState(), [], ()), "source projectiles"),  # type: ignore[arg-type]
        (lambda: resolve_projectile_suppression(MissionState(), (), []), "projectile impacts"),  # type: ignore[arg-type]
    ),
)
def test_suppression_resolution_rejects_invalid_inputs(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def _state_with_entities(*positions: WorldPosition) -> tuple[MissionState, tuple[EntityState, ...]]:
    state = MissionState()
    entities: list[EntityState] = []
    for entity_position in positions:
        state, entity = add_entity(state, entity_position)
        entities.append(entity)
    return state, tuple(entities)


def _with_projectile(state: MissionState, owner: EntityState) -> MissionState:
    projectile_id, allocator = state.id_allocator.allocate_projectile()
    intention_id, allocator = allocator.allocate_intention()
    invocation_id, allocator = allocator.allocate_policy_invocation()
    projectile = Projectile(
        projectile_id,
        owner.entity_id,
        ProjectileProvenance(
            IntentionOrigin(
                intention_id,
                owner.entity_id,
                invocation_id,
                ExpressionId(0),
                _SOURCE.span(ByteOffset(0), ByteOffset(0)),
                0,
                state.tick,
                IntentionKind.FIRE,
            )
        ),
        position(0, 0),
        WorldVector(WorldSubunits(1_000), WorldSubunits(0)),
        3,
    )
    return replace(
        state,
        id_allocator=allocator,
        projectiles=ProjectileStore(state.projectiles.entries + (projectile,)),
    )


def _resolution_for(phase: SuppressionPhase, entity: EntityState) -> SuppressionResolution:
    return next(
        resolution for resolution in phase.resolutions if resolution.entity_id == entity.entity_id
    )


_SOURCE = SourceFile(SourceFileId("suppression-test.dtr"), "")


def position(x: int, y: int, elevation: int = 0) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y), ElevationLayer(elevation))
