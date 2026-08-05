from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import (
    ElevationLayer,
    WorldPosition,
    WorldRectangle,
    WorldSubunits,
    WorldVector,
)
from kiwi.domain.ids import CoverId, IdAllocator, ObstacleId
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.combat_events import emit_projectile_events
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)
from kiwi.sim.events import ProjectileAdvanced, ProjectileExpired, ProjectileImpacted
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.projectile_impacts import (
    ProjectileImpact,
    ProjectileImpactPhase,
    advance_projectiles,
    resolve_projectile_impacts,
)
from kiwi.sim.projectile_sweeps import ProjectileCollisionKind
from kiwi.sim.projectiles import Projectile, ProjectileStore
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.state import MissionState, add_entity


def test_advance_projectiles_moves_a_survivor_and_decrements_its_lifetime() -> None:
    state = _state_with_projectile()
    projectile = state.projectiles.entries[0]

    phase = resolve_projectile_impacts(state)

    assert phase.impacts == ()
    assert phase.state.projectiles.entries == (
        replace(projectile, position=position(1_000, 0), remaining_ticks=2),
    )
    assert advance_projectiles(state) == phase.state
    assert state.projectiles.entries == (projectile,)


def test_projectile_expiration_occurs_after_its_final_unobstructed_segment() -> None:
    phase = resolve_projectile_impacts(_state_with_projectile(remaining_ticks=1))

    assert phase.impacts == ()
    assert phase.state.projectiles == ProjectileStore()


def test_projectile_outcome_events_retain_advance_expiry_and_impact_results() -> None:
    advanced = emit_projectile_events(resolve_projectile_impacts(_state_with_projectile()))
    expired = emit_projectile_events(
        resolve_projectile_impacts(_state_with_projectile(remaining_ticks=1))
    )
    obstacle_id = ObstacleId(1)
    geometry = MapGeometry(
        rectangle(-2_000, -2_000, 2_000, 2_000),
        (MapObstacle(obstacle_id, rectangle(400, -100, 600, 100)),),
    )
    impacted = emit_projectile_events(
        resolve_projectile_impacts(
            _state_with_projectile(map_geometry=geometry, obstacle_ids=(obstacle_id,))
        )
    )

    assert isinstance(advanced.events[0], ProjectileAdvanced)
    assert isinstance(expired.events[0], ProjectileExpired)
    assert isinstance(impacted.events[0], ProjectileImpacted)
    assert impacted.events[0].impact.collision.target_id == obstacle_id


def test_obstacle_impact_consumes_the_projectile_at_its_collision_point() -> None:
    obstacle_id = ObstacleId(1)
    geometry = MapGeometry(
        rectangle(-2_000, -2_000, 2_000, 2_000),
        (MapObstacle(obstacle_id, rectangle(400, -100, 600, 100)),),
    )
    phase = resolve_projectile_impacts(
        _state_with_projectile(map_geometry=geometry, obstacle_ids=(obstacle_id,))
    )

    impact = _only_impact(phase)

    assert impact.collision.kind is ProjectileCollisionKind.OBSTACLE
    assert impact.collision.target_id == obstacle_id
    assert impact.collision.position == position(400, 0)


def test_cover_impact_consumes_the_projectile_at_its_collision_point() -> None:
    cover_id = CoverId(1)
    phase = resolve_projectile_impacts(
        _state_with_projectile(
            covers=CoverStore((_cover(cover_id, 500),)),
            cover_ids=(cover_id,),
        )
    )

    impact = _only_impact(phase)

    assert impact.collision.kind is ProjectileCollisionKind.COVER
    assert impact.collision.target_id == cover_id
    assert impact.collision.position == position(500, 0)


def test_operative_impact_consumes_the_projectile_at_its_collision_point() -> None:
    state = _state_with_projectile(target_x=850)
    target_id = state.entities[1].entity_id

    impact = _only_impact(resolve_projectile_impacts(state))

    assert impact.collision.kind is ProjectileCollisionKind.OPERATIVE
    assert impact.collision.target_id == target_id
    assert impact.collision.position == position(500, 0)


def test_projectiles_can_advance_beyond_map_bounds_until_boundary_removal_exists() -> None:
    geometry = MapGeometry(rectangle(-2_000, -2_000, 2_000, 2_000))
    state = _state_with_projectile(map_geometry=geometry, projectile_start=position(1_900, 0))

    phase = resolve_projectile_impacts(state)

    assert phase.impacts == ()
    assert phase.state.projectiles.entries[0].position == position(2_900, 0)


def test_active_reducer_resolves_projectile_impact_before_clock_advance() -> None:
    state = _state_with_projectile()

    result = reduce_one_tick(
        state,
        FixedTickClock(TickRate.HZ_30),
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
    )

    assert result.state.tick == 1
    assert result.state.projectiles.entries[0].position == position(1_000, 0)
    assert result.state.projectiles.entries[0].remaining_ticks == 2


def test_active_reducer_consumes_a_collided_projectile_before_clock_advance() -> None:
    obstacle_id = ObstacleId(1)
    geometry = MapGeometry(
        rectangle(-2_000, -2_000, 2_000, 2_000),
        (MapObstacle(obstacle_id, rectangle(400, -100, 600, 100)),),
    )
    state = _state_with_projectile(map_geometry=geometry, obstacle_ids=(obstacle_id,))

    result = reduce_one_tick(
        state,
        FixedTickClock(TickRate.HZ_30),
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
    )

    assert result.state.tick == 1
    assert result.state.projectiles == ProjectileStore()


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: resolve_projectile_impacts(object()), "mission state"),  # type: ignore[arg-type]
        (
            lambda: ProjectileImpactPhase(MissionState(), (object(),)),  # type: ignore[arg-type]
            "contain projectile impacts",
        ),
    ),
)
def test_projectile_impact_values_reject_invalid_inputs(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def _only_impact(phase: ProjectileImpactPhase) -> ProjectileImpact:
    assert phase.state.projectiles == ProjectileStore()
    assert len(phase.impacts) == 1
    return phase.impacts[0]


def _state_with_projectile(
    *,
    map_geometry: MapGeometry | None = None,
    obstacle_ids: tuple[ObstacleId, ...] = (),
    covers: CoverStore | None = None,
    cover_ids: tuple[CoverId, ...] = (),
    target_x: int | None = None,
    projectile_start: WorldPosition | None = None,
    remaining_ticks: int = 3,
) -> MissionState:
    allocator = IdAllocator()
    for expected_obstacle_id in obstacle_ids:
        obstacle_id, allocator = allocator.allocate_obstacle()
        assert obstacle_id == expected_obstacle_id
    state = MissionState(map_geometry=map_geometry, id_allocator=allocator)
    allocator = state.id_allocator
    for expected_cover_id in cover_ids:
        cover_id, allocator = allocator.allocate_cover()
        assert cover_id == expected_cover_id
    state = replace(
        state,
        id_allocator=allocator,
        covers=CoverStore() if covers is None else covers,
    )
    state, owner = add_entity(state, position(-1_000, 1_000))
    if target_x is not None:
        state, _ = add_entity(state, position(target_x, 0))
    projectile_id, allocator = state.id_allocator.allocate_projectile()
    intention_id, allocator = allocator.allocate_intention()
    projectile = Projectile(
        projectile_id,
        owner.entity_id,
        intention_id,
        position(0, 0) if projectile_start is None else projectile_start,
        WorldVector(WorldSubunits(1_000), WorldSubunits(0)),
        remaining_ticks,
    )
    return replace(state, id_allocator=allocator, projectiles=ProjectileStore((projectile,)))


def _cover(cover_id: CoverId, x: int) -> CoverSegment:
    return CoverSegment(
        cover_id,
        position(x, -100),
        position(x, 100),
        CoverHeight.HIGH,
        CoverIntegrity(10_000),
        (CoverSlot(0, position(x, -200), CoverSide.LEFT),),
    )


def position(x: int, y: int, elevation: int = 0) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y), ElevationLayer(elevation))


def rectangle(minimum_x: int, minimum_y: int, maximum_x: int, maximum_y: int) -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(minimum_x),
        WorldSubunits(minimum_y),
        WorldSubunits(maximum_x),
        WorldSubunits(maximum_y),
    )
