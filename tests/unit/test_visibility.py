from __future__ import annotations

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import ObstacleId
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.visibility import (
    VisibilityQuery,
    VisibilityQueryCode,
    VisibilityQueryFailure,
    VisibilityStatus,
    prepare_visibility_query,
    resolve_visibility,
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


def map_geometry(obstacles: tuple[MapObstacle, ...] = ()) -> MapGeometry:
    return MapGeometry(rectangle(-2_000, -2_000, 2_000, 2_000), obstacles)


def test_same_layer_visibility_is_visible_without_an_occluding_obstacle() -> None:
    query = prepare_visibility_query(map_geometry(), position(-1_000, 0), position(1_000, 0))

    assert isinstance(query, VisibilityQuery)
    assert resolve_visibility(query).status is VisibilityStatus.VISIBLE


def test_visibility_uses_the_lowest_id_same_layer_occluding_obstacle() -> None:
    geometry = map_geometry(
        (
            MapObstacle(ObstacleId(1), rectangle(-500, -100, -400, 100)),
            MapObstacle(ObstacleId(2), rectangle(400, -100, 500, 100)),
        )
    )
    query = VisibilityQuery(geometry, position(-1_000, 0), position(1_000, 0))

    first = resolve_visibility(query)
    second = resolve_visibility(query)

    assert first == second
    assert first.status is VisibilityStatus.OBSTACLE_BLOCKED
    assert first.blocking_obstacle_id == ObstacleId(1)


def test_visibility_treats_closed_obstacle_corner_contacts_as_occluding() -> None:
    geometry = map_geometry((MapObstacle(ObstacleId(1), rectangle(0, 0, 500, 500)),))
    query = VisibilityQuery(geometry, position(-1_000, 1_000), position(1_000, -1_000))

    result = resolve_visibility(query)

    assert result.status is VisibilityStatus.OBSTACLE_BLOCKED
    assert result.blocking_obstacle_id == ObstacleId(1)


def test_visibility_ignores_other_layer_obstacles_and_blocks_cross_layer_targets() -> None:
    geometry = map_geometry(
        (MapObstacle(ObstacleId(1), rectangle(-500, -500, 500, 500), ElevationLayer(1)),)
    )

    same_layer = resolve_visibility(
        VisibilityQuery(geometry, position(-1_000, 0), position(1_000, 0))
    )
    cross_layer = resolve_visibility(
        VisibilityQuery(geometry, position(-1_000, 0), position(1_000, 0, 1))
    )

    assert same_layer.status is VisibilityStatus.VISIBLE
    assert cross_layer.status is VisibilityStatus.ELEVATION_BLOCKED
    assert cross_layer.blocking_obstacle_id is None


@pytest.mark.parametrize(
    ("geometry", "observer", "target", "code"),
    (
        (None, position(0, 0), position(1, 1), VisibilityQueryCode.MISSING_MAP),
        (
            map_geometry(),
            position(-2_001, 0),
            position(0, 0),
            VisibilityQueryCode.OBSERVER_OUTSIDE_MAP,
        ),
        (
            map_geometry(),
            position(0, 0),
            position(2_001, 0),
            VisibilityQueryCode.TARGET_OUTSIDE_MAP,
        ),
    ),
)
def test_visibility_query_returns_structured_precondition_failures(
    geometry: MapGeometry | None,
    observer: WorldPosition,
    target: WorldPosition,
    code: VisibilityQueryCode,
) -> None:
    result = prepare_visibility_query(geometry, observer, target)

    assert isinstance(result, VisibilityQueryFailure)
    assert result.code is code


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: VisibilityQuery(map_geometry(), position(-2_001, 0), position(0, 0)),
            "within map",
        ),
        (lambda: resolve_visibility(object()), "visibility query"),  # type: ignore[arg-type]
    ),
)
def test_visibility_values_reject_invalid_inputs(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
