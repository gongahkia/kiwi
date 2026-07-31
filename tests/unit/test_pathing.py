from __future__ import annotations

from typing import cast

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import ObstacleId
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.pathing import (
    MAX_PATH_OBSTACLES,
    Path,
    PathQuery,
    PathQueryCode,
    PathQueryFailure,
    PathSearchCode,
    PathSearchFailure,
    find_path,
    prepare_path_query,
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
    return MapGeometry(rectangle(-5_000, -5_000, 5_000, 5_000), obstacles)


def test_path_query_and_path_preserve_canonical_waypoint_order() -> None:
    query = prepare_path_query(map_geometry(), position(-500, 0), position(500, 0))

    assert isinstance(query, PathQuery)
    path = Path(query, (position(-500, 0), position(0, 500), position(500, 0)))
    assert path.waypoints == (position(-500, 0), position(0, 500), position(500, 0))


def test_arrived_path_is_one_waypoint_at_the_query_endpoint() -> None:
    query = prepare_path_query(map_geometry(), position(0, 0), position(0, 0))

    assert isinstance(query, PathQuery)
    assert Path(query, (position(0, 0),)).waypoints == (position(0, 0),)


def test_visibility_routing_uses_stable_lower_lexicographic_obstacle_route() -> None:
    geometry = map_geometry((MapObstacle(ObstacleId(1), rectangle(-500, -500, 500, 500)),))
    query = PathQuery(geometry, position(-2_000, 0), position(2_000, 0))

    first = find_path(query)
    second = find_path(query)

    assert isinstance(first, Path)
    assert second == first
    assert first.waypoints == (
        position(-2_000, 0),
        position(-851, -851),
        position(851, -851),
        position(2_000, 0),
    )


def test_visibility_routing_ignores_obstacles_at_other_elevations() -> None:
    geometry = map_geometry(
        (MapObstacle(ObstacleId(1), rectangle(-500, -500, 500, 500), ElevationLayer(1)),)
    )
    query = PathQuery(geometry, position(-2_000, 0), position(2_000, 0))

    result = find_path(query)

    assert result == Path(query, (position(-2_000, 0), position(2_000, 0)))


@pytest.mark.parametrize(
    ("geometry", "start", "goal", "code"),
    (
        (
            map_geometry((MapObstacle(ObstacleId(1), rectangle(-500, -500, 500, 500)),)),
            position(-850, 0),
            position(2_000, 0),
            PathSearchCode.START_BLOCKED,
        ),
        (
            map_geometry(),
            position(0, 0),
            position(5_000, 0),
            PathSearchCode.GOAL_BLOCKED,
        ),
        (
            map_geometry((MapObstacle(ObstacleId(1), rectangle(-100, -5_000, 100, 5_000)),)),
            position(-2_000, 0),
            position(2_000, 0),
            PathSearchCode.NO_ROUTE,
        ),
    ),
)
def test_visibility_routing_reports_structured_failures(
    geometry: MapGeometry,
    start: WorldPosition,
    goal: WorldPosition,
    code: PathSearchCode,
) -> None:
    result = find_path(PathQuery(geometry, start, goal))

    assert isinstance(result, PathSearchFailure)
    assert result.code is code


def test_visibility_routing_enforces_the_same_layer_obstacle_budget() -> None:
    obstacles = tuple(
        MapObstacle(
            ObstacleId(index + 1),
            rectangle(-4_000 + index * 100, -10, -3_950 + index * 100, 10),
        )
        for index in range(MAX_PATH_OBSTACLES + 1)
    )
    query = PathQuery(map_geometry(obstacles), position(0, 0), position(2_000, 0))

    result = find_path(query)

    assert result == PathSearchFailure(
        PathSearchCode.OBSTACLE_BUDGET_EXCEEDED,
        "path query exceeds the configured obstacle budget",
    )


@pytest.mark.parametrize(
    ("map_value", "start", "goal", "code"),
    (
        (None, position(0, 0), position(1, 1), PathQueryCode.MISSING_MAP),
        (map_geometry(), position(0, 0, 0), position(0, 0, 1), PathQueryCode.ELEVATION_MISMATCH),
        (map_geometry(), position(-5_001, 0), position(0, 0), PathQueryCode.START_OUTSIDE_MAP),
        (map_geometry(), position(0, 0), position(5_001, 0), PathQueryCode.GOAL_OUTSIDE_MAP),
    ),
)
def test_path_query_reports_structured_precondition_failures(
    map_value: MapGeometry | None,
    start: WorldPosition,
    goal: WorldPosition,
    code: PathQueryCode,
) -> None:
    result = prepare_path_query(map_value, start, goal)

    assert isinstance(result, PathQueryFailure)
    assert result.code is code


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: PathQuery(map_geometry(), position(0, 0), position(0, 0, 1)), "elevation"),
        (lambda: PathQuery(map_geometry(), position(0, 0), position(5_001, 0)), "within map"),
        (
            lambda: Path(
                PathQuery(map_geometry(), position(0, 0), position(1, 1)),
                cast(tuple[WorldPosition, ...], []),
            ),
            "immutable tuple",
        ),
        (
            lambda: Path(
                PathQuery(map_geometry(), position(0, 0), position(1, 1)),
                cast(tuple[WorldPosition, ...], (object(), position(1, 1))),
            ),
            "world positions",
        ),
        (
            lambda: Path(
                PathQuery(map_geometry(), position(0, 0), position(1, 1)),
                (position(1, 1), position(0, 0)),
            ),
            "begin",
        ),
        (
            lambda: Path(
                PathQuery(map_geometry(), position(0, 0), position(1, 1)),
                (position(0, 0), position(0, 0), position(1, 1)),
            ),
            "repeat consecutively",
        ),
        (
            lambda: Path(
                PathQuery(map_geometry(), position(0, 0), position(0, 0)),
                (position(0, 0), position(1, 1), position(0, 0)),
            ),
            "exactly one",
        ),
    ),
)
def test_path_values_reject_noncanonical_waypoints(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
