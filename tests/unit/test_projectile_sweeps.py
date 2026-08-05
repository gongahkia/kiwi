from __future__ import annotations

from dataclasses import replace

from kiwi.domain.geometry import (
    ElevationLayer,
    WorldPosition,
    WorldRectangle,
    WorldSubunits,
    WorldVector,
)
from kiwi.domain.ids import CoverId, IdAllocator, ObstacleId, ProjectileId
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.projectile_sweeps import (
    PROJECTILE_SWEEP_TIME_SUBTICKS,
    ProjectileCollision,
    ProjectileCollisionKind,
    sweep_projectiles,
)
from kiwi.sim.projectiles import Projectile, ProjectileStore
from kiwi.sim.state import MissionState, add_entity


def test_sweep_projectiles_advances_without_collision_or_state_mutation() -> None:
    state = _state_with_projectile()

    sweeps = sweep_projectiles(state)

    assert sweeps[0].projectile_id == ProjectileId(1)
    assert sweeps[0].start_position == position(0, 0)
    assert sweeps[0].end_position == position(1_000, 0)
    assert sweeps[0].collision is None
    assert state.projectiles.entries[0].position == position(0, 0)
    assert state.projectiles.entries[0].remaining_ticks == 3


def test_sweep_projectiles_prevents_tunnelling_through_obstacle() -> None:
    obstacle_id = ObstacleId(1)
    geometry = MapGeometry(
        rectangle(-2_000, -2_000, 2_000, 2_000),
        (MapObstacle(obstacle_id, rectangle(400, -100, 600, 100)),),
    )
    state = _state_with_projectile(map_geometry=geometry, obstacle_ids=(obstacle_id,))

    collision = sweep_projectiles(state)[0].collision

    assert collision is not None
    assert collision.kind is ProjectileCollisionKind.OBSTACLE
    assert collision.target_id == obstacle_id
    assert collision.position == position(400, 0)
    assert 0 < collision.subtick < PROJECTILE_SWEEP_TIME_SUBTICKS


def test_equal_time_cover_collision_precedes_operative_collision() -> None:
    cover_id = CoverId(1)
    cover = _cover(cover_id, 500)
    state = _state_with_projectile(
        covers=CoverStore((cover,)), cover_ids=(cover_id,), targets=(850,)
    )

    collision = sweep_projectiles(state)[0].collision

    assert collision is not None
    assert collision.kind is ProjectileCollisionKind.COVER
    assert collision.target_id == cover_id
    assert collision.position == position(500, 0)
    assert len(state.entities) == 2


def test_equal_time_obstacle_collision_precedes_cover_collision() -> None:
    obstacle_id = ObstacleId(1)
    cover_id = CoverId(1)
    geometry = MapGeometry(
        rectangle(-2_000, -2_000, 2_000, 2_000),
        (MapObstacle(obstacle_id, rectangle(500, -100, 600, 100)),),
    )
    state = _state_with_projectile(
        map_geometry=geometry,
        obstacle_ids=(obstacle_id,),
        covers=CoverStore((_cover(cover_id, 500),)),
        cover_ids=(cover_id,),
    )

    collision = sweep_projectiles(state)[0].collision

    assert collision is not None
    assert collision.kind is ProjectileCollisionKind.OBSTACLE
    assert collision.target_id == obstacle_id
    assert collision.position == position(500, 0)


def test_equal_time_cover_collision_uses_lowest_stable_id() -> None:
    first_cover_id = CoverId(1)
    second_cover_id = CoverId(2)
    state = _state_with_projectile(
        covers=CoverStore((_cover(first_cover_id, 500), _cover(second_cover_id, 500))),
        cover_ids=(first_cover_id, second_cover_id),
    )

    collision = sweep_projectiles(state)[0].collision

    assert collision is not None
    assert collision.kind is ProjectileCollisionKind.COVER
    assert collision.target_id == first_cover_id


def test_sweep_ignores_other_elevation_collision_candidates() -> None:
    obstacle_id = ObstacleId(1)
    geometry = MapGeometry(
        rectangle(-2_000, -2_000, 2_000, 2_000),
        (MapObstacle(obstacle_id, rectangle(400, -100, 600, 100), ElevationLayer(1)),),
    )
    state = _state_with_projectile(map_geometry=geometry, obstacle_ids=(obstacle_id,))

    assert sweep_projectiles(state)[0].collision is None


def test_projectile_collision_rejects_a_target_id_of_the_wrong_class() -> None:
    try:
        ProjectileCollision(
            ProjectileCollisionKind.OBSTACLE,
            CoverId(1),
            0,
            position(0, 0),
        )
    except ValueError as error:
        assert str(error) == "projectile collision target does not match its kind"
    else:
        raise AssertionError("projectile collision accepted a cover as an obstacle")


def _state_with_projectile(
    *,
    map_geometry: MapGeometry | None = None,
    obstacle_ids: tuple[ObstacleId, ...] = (),
    covers: CoverStore | None = None,
    cover_ids: tuple[CoverId, ...] = (),
    targets: tuple[int, ...] = (),
) -> MissionState:
    allocator = IdAllocator()
    for expected_id in obstacle_ids:
        allocated_obstacle_id, allocator = allocator.allocate_obstacle()
        assert allocated_obstacle_id == expected_id
    state = MissionState(map_geometry=map_geometry, id_allocator=allocator)
    allocator = state.id_allocator
    for expected_cover_id in cover_ids:
        allocated_cover_id, allocator = allocator.allocate_cover()
        assert allocated_cover_id == expected_cover_id
    state = replace(
        state, id_allocator=allocator, covers=CoverStore() if covers is None else covers
    )
    state, owner = add_entity(state, position(-1_000, 1_000))
    for target_x in targets:
        state, _ = add_entity(state, position(target_x, 0))
    projectile_id, allocator = state.id_allocator.allocate_projectile()
    intention_id, allocator = allocator.allocate_intention()
    projectile = Projectile(
        projectile_id,
        owner.entity_id,
        intention_id,
        position(0, 0),
        WorldVector(WorldSubunits(1_000), WorldSubunits(0)),
        3,
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
