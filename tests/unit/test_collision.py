from __future__ import annotations

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import ObstacleId
from kiwi.sim.collision import (
    movement_segment_collides_map,
    movement_segments_violate_separation,
)
from kiwi.sim.map_geometry import MapGeometry, MapObstacle


def position(x: int, y: int, elevation: int = 0) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y), ElevationLayer(elevation))


def rectangle(minimum_x: int, minimum_y: int, maximum_x: int, maximum_y: int) -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(minimum_x),
        WorldSubunits(minimum_y),
        WorldSubunits(maximum_x),
        WorldSubunits(maximum_y),
    )


def map_geometry(obstacles: tuple[MapObstacle, ...] = ()) -> MapGeometry:
    return MapGeometry(rectangle(-2_000, -2_000, 2_000, 2_000), obstacles)


def test_swept_disc_collision_blocks_map_boundaries_and_thin_obstacles() -> None:
    thin_wall = MapObstacle(ObstacleId(1), rectangle(0, -10, 1, 10))

    assert movement_segment_collides_map(position(-1_800, 0), position(-1_650, 0), map_geometry())
    assert movement_segment_collides_map(
        position(-500, 0), position(500, 0), map_geometry((thin_wall,))
    )


def test_disc_collision_uses_exact_euclidean_corner_clearance() -> None:
    obstacle = MapObstacle(ObstacleId(1), rectangle(0, 0, 100, 100))
    geometry = map_geometry((obstacle,))

    assert movement_segment_collides_map(position(-247, -247), position(-247, -247), geometry)
    assert not movement_segment_collides_map(position(-248, -248), position(-248, -248), geometry)


def test_separation_treats_disc_contact_and_crossing_as_collisions() -> None:
    assert movement_segments_violate_separation(
        position(0, 0), position(0, 0), position(700, 0), position(700, 0)
    )
    assert movement_segments_violate_separation(
        position(-1_000, 0), position(1_000, 0), position(0, -1_000), position(0, 1_000)
    )
    assert not movement_segments_violate_separation(
        position(0, 0, 0), position(0, 0, 0), position(0, 0, 1), position(0, 0, 1)
    )
