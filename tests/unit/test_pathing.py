from __future__ import annotations

from typing import cast

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle, WorldSubunits
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.pathing import Path, PathQuery, PathQueryCode, PathQueryFailure, prepare_path_query


def position(x: int, y: int, elevation: int = 0) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y), ElevationLayer(elevation))


def map_geometry() -> MapGeometry:
    return MapGeometry(
        WorldRectangle(
            WorldSubunits(-1_000), WorldSubunits(-1_000), WorldSubunits(1_000), WorldSubunits(1_000)
        )
    )


def test_path_query_and_path_preserve_canonical_waypoint_order() -> None:
    query = prepare_path_query(map_geometry(), position(-500, 0), position(500, 0))

    assert isinstance(query, PathQuery)
    path = Path(query, (position(-500, 0), position(0, 500), position(500, 0)))
    assert path.waypoints == (position(-500, 0), position(0, 500), position(500, 0))


def test_arrived_path_is_one_waypoint_at_the_query_endpoint() -> None:
    query = prepare_path_query(map_geometry(), position(0, 0), position(0, 0))

    assert isinstance(query, PathQuery)
    assert Path(query, (position(0, 0),)).waypoints == (position(0, 0),)


@pytest.mark.parametrize(
    ("map_value", "start", "goal", "code"),
    (
        (None, position(0, 0), position(1, 1), PathQueryCode.MISSING_MAP),
        (map_geometry(), position(0, 0, 0), position(0, 0, 1), PathQueryCode.ELEVATION_MISMATCH),
        (map_geometry(), position(-1_001, 0), position(0, 0), PathQueryCode.START_OUTSIDE_MAP),
        (map_geometry(), position(0, 0), position(1_001, 0), PathQueryCode.GOAL_OUTSIDE_MAP),
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
        (lambda: PathQuery(map_geometry(), position(0, 0), position(1_001, 0)), "within map"),
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
