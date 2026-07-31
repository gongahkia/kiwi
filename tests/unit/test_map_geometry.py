from __future__ import annotations

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import IdAllocator, ObstacleId
from kiwi.sim.map_geometry import MapGeometry, MapObstacle


def rectangle(minimum_x: int, minimum_y: int, maximum_x: int, maximum_y: int) -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(minimum_x),
        WorldSubunits(minimum_y),
        WorldSubunits(maximum_x),
        WorldSubunits(maximum_y),
    )


def test_map_geometry_uses_closed_bounds_and_ascending_obstacle_ids() -> None:
    geometry = MapGeometry(
        rectangle(-1_000, -1_000, 1_000, 1_000),
        (
            MapObstacle(ObstacleId(1), rectangle(-500, -500, 0, 0)),
            MapObstacle(ObstacleId(2), rectangle(0, 0, 500, 500), ElevationLayer(2)),
        ),
    )

    assert geometry.contains_position(WorldPosition(WorldSubunits(-1_000), WorldSubunits(1_000)))
    assert not geometry.contains_position(WorldPosition(WorldSubunits(1_001), WorldSubunits(1_000)))
    assert geometry.obstacles[1].elevation == ElevationLayer(2)


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: MapObstacle(ObstacleId(1), rectangle(0, 0, 1, 1), elevation=object()),  # type: ignore[arg-type]
            "elevation",
        ),
        (
            lambda: MapGeometry(rectangle(0, 0, 10, 10), []),  # type: ignore[arg-type]
            "immutable tuple",
        ),
        (
            lambda: MapGeometry(
                rectangle(0, 0, 10, 10),
                (
                    MapObstacle(ObstacleId(2), rectangle(0, 0, 1, 1)),
                    MapObstacle(ObstacleId(1), rectangle(2, 2, 3, 3)),
                ),
            ),
            "ascending",
        ),
        (
            lambda: MapGeometry(
                rectangle(0, 0, 10, 10),
                (MapObstacle(ObstacleId(1), rectangle(-1, 0, 1, 1)),),
            ),
            "within map bounds",
        ),
    ),
)
def test_map_geometry_rejects_noncanonical_values(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def test_obstacle_ids_use_the_type_local_allocator() -> None:
    obstacle, allocator = IdAllocator().allocate_obstacle()

    assert obstacle == ObstacleId(1)
    assert allocator.allocate_obstacle()[0] == ObstacleId(2)
