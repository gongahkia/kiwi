from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits, WorldVector
from kiwi.domain.ids import EntityId
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.combat_events import emit_damage_events, emit_projectile_events
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.conditions import InjurySeverity, OperativeCondition, OperativeConditionStore
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverReservation,
    CoverReservationStore,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)
from kiwi.sim.damage import PROJECTILE_IMPACT_DAMAGE, resolve_projectile_damage
from kiwi.sim.events import DamageApplied, InjuryChanged, ProjectileImpacted
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.projectile_impacts import ProjectileImpact, resolve_projectile_impacts
from kiwi.sim.projectile_sweeps import ProjectileCollision, ProjectileCollisionKind
from kiwi.sim.projectiles import Projectile, ProjectileStore
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.state import EntityState, MissionState, MovementAction, add_entity


def test_projectile_damage_consumes_protection_then_progresses_injury_bands() -> None:
    state, target = _state_with_target()
    state, impacts = _operative_impacts(state, target.entity_id, 4)

    phase = resolve_projectile_damage(state, impacts)

    assert PROJECTILE_IMPACT_DAMAGE == 1
    assert tuple(resolution.protection_absorbed for resolution in phase.resolutions) == (1, 0, 0, 0)
    assert tuple(resolution.health_damage for resolution in phase.resolutions) == (0, 1, 1, 1)
    assert tuple(resolution.health_after for resolution in phase.resolutions) == (3, 2, 1, 0)
    assert tuple(resolution.injury_after for resolution in phase.resolutions) == (
        InjurySeverity.NONE,
        InjurySeverity.MINOR,
        InjurySeverity.SEVERE,
        InjurySeverity.INCAPACITATED,
    )
    assert phase.resolutions[-1].became_incapacitated
    assert phase.state.conditions.condition_for(target.entity_id) == OperativeCondition(
        target.entity_id, 0, 0
    )


def test_injury_clears_stabilization_when_health_damage_occurs() -> None:
    state, target = _state_with_target()
    state = replace(
        state,
        conditions=OperativeConditionStore((OperativeCondition(target.entity_id, 2, 0, True),)),
    )
    state, impacts = _operative_impacts(state, target.entity_id, 1)

    resolution = resolve_projectile_damage(state, impacts).resolutions[0]

    assert resolution.stabilized_before
    assert not resolution.stabilized_after
    assert resolution.health_after == 1


def test_damage_events_parent_impacts_and_injury_events_parent_damage() -> None:
    state, target = _state_with_target()
    state = replace(
        state,
        conditions=OperativeConditionStore((OperativeCondition(target.entity_id, 2, 0),)),
    )
    state = _with_live_projectiles(state, target.entity_id, 1)
    impacts = resolve_projectile_impacts(state)
    projectile_events = emit_projectile_events(impacts)
    damage = resolve_projectile_damage(projectile_events.state, impacts.impacts)

    emitted = emit_damage_events(damage, projectile_events.events)

    impact_event = next(
        event for event in projectile_events.events if isinstance(event, ProjectileImpacted)
    )
    damage_event = next(event for event in emitted.events if isinstance(event, DamageApplied))
    injury_event = next(event for event in emitted.events if isinstance(event, InjuryChanged))
    assert damage_event.header.parent_event_ids == (impact_event.header.event_id,)
    assert injury_event.header.parent_event_ids == (damage_event.header.event_id,)
    assert injury_event.resolution.injury_after is InjurySeverity.SEVERE


def test_incapacitation_cancels_existing_movement_actions_and_cover_reservations() -> None:
    geometry = MapGeometry(rectangle(-2_000, -2_000, 2_000, 2_000))
    state, target = _state_with_target(geometry)
    goal = position(1_000, 0)
    path = Path(PathQuery(geometry, target.position, goal), (target.position, goal))
    cover_id, allocator = state.id_allocator.allocate_cover()
    intention_id, allocator = allocator.allocate_intention()
    cover = CoverSegment(
        cover_id,
        position(0, 100),
        position(100, 100),
        CoverHeight.HIGH,
        CoverIntegrity(10_000),
        (CoverSlot(0, position(0, 0), CoverSide.LEFT),),
    )
    state = replace(
        state,
        movement_actions=(MovementAction(target.entity_id, path),),
        id_allocator=allocator,
        covers=CoverStore((cover,)),
        cover_reservations=CoverReservationStore(
            (CoverReservation(cover_id, 0, target.entity_id, intention_id),)
        ),
    )
    state, impacts = _operative_impacts(state, target.entity_id, 4)

    phase = resolve_projectile_damage(state, impacts)

    assert phase.state.conditions.is_incapacitated(target.entity_id)
    assert phase.state.movement_actions == ()
    assert phase.state.cover_reservations == CoverReservationStore()


def test_reducer_applies_damage_from_live_projectile_impacts() -> None:
    state, target = _state_with_target()
    state = _with_live_projectiles(state, target.entity_id, 4)

    result = reduce_one_tick(
        state,
        FixedTickClock(TickRate.HZ_30),
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
    )

    assert result.state.tick == 1
    assert result.state.projectiles == ProjectileStore()
    assert result.state.conditions.condition_for(target.entity_id) == OperativeCondition(
        target.entity_id, 0, 0
    )


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: resolve_projectile_damage(object(), ()), "mission state"),  # type: ignore[arg-type]
        (lambda: resolve_projectile_damage(MissionState(), []), "immutable"),  # type: ignore[arg-type]
    ),
)
def test_damage_resolution_rejects_invalid_inputs(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def _state_with_target(map_geometry: MapGeometry | None = None) -> tuple[MissionState, EntityState]:
    state, _ = add_entity(MissionState(map_geometry=map_geometry), position(-1_000, 1_000))
    return add_entity(state, position(850, 0))


def _operative_impacts(
    state: MissionState,
    target_entity_id: EntityId,
    count: int,
) -> tuple[MissionState, tuple[ProjectileImpact, ...]]:
    allocator = state.id_allocator
    impacts: list[ProjectileImpact] = []
    owner_entity_id = state.entities[0].entity_id
    for _ in range(count):
        projectile_id, allocator = allocator.allocate_projectile()
        intention_id, allocator = allocator.allocate_intention()
        projectile = Projectile(
            projectile_id,
            owner_entity_id,
            intention_id,
            position(0, 0),
            WorldVector(WorldSubunits(1_000), WorldSubunits(0)),
            1,
        )
        impacts.append(
            ProjectileImpact(
                state.tick,
                projectile,
                ProjectileCollision(
                    ProjectileCollisionKind.OPERATIVE,
                    target_entity_id,
                    0,
                    position(500, 0),
                ),
            )
        )
    return replace(state, id_allocator=allocator), tuple(impacts)


def _with_live_projectiles(
    state: MissionState,
    target_entity_id: EntityId,
    count: int,
) -> MissionState:
    state, impacts = _operative_impacts(state, target_entity_id, count)
    return replace(
        state, projectiles=ProjectileStore(tuple(impact.projectile for impact in impacts))
    )


def position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def rectangle(minimum_x: int, minimum_y: int, maximum_x: int, maximum_y: int) -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(minimum_x),
        WorldSubunits(minimum_y),
        WorldSubunits(maximum_x),
        WorldSubunits(maximum_y),
    )
