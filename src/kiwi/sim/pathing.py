"""Deterministic path-query values before a pathfinding algorithm is selected."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.geometry import WorldPosition
from kiwi.sim.map_geometry import MapGeometry


class PathQueryCode(StrEnum):
    """Stable outcomes for path-query precondition validation."""

    MISSING_MAP = "P001_MISSING_MAP"
    ELEVATION_MISMATCH = "P002_ELEVATION_MISMATCH"
    START_OUTSIDE_MAP = "P003_START_OUTSIDE_MAP"
    GOAL_OUTSIDE_MAP = "P004_GOAL_OUTSIDE_MAP"


@dataclass(frozen=True, slots=True)
class PathQueryFailure:
    """One structured path-query precondition failure."""

    code: PathQueryCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, PathQueryCode):
            raise ValueError("path query failure requires a path query code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("path query failure requires a non-empty message")


@dataclass(frozen=True, slots=True)
class PathQuery:
    """One validated, immutable same-layer route request over one map."""

    map_geometry: MapGeometry
    start: WorldPosition
    goal: WorldPosition

    def __post_init__(self) -> None:
        if not isinstance(self.map_geometry, MapGeometry):
            raise ValueError("path query requires map geometry")
        if not isinstance(self.start, WorldPosition) or not isinstance(self.goal, WorldPosition):
            raise ValueError("path query endpoints must be world positions")
        if self.start.elevation != self.goal.elevation:
            raise ValueError("path query endpoints must share an elevation layer")
        if not self.map_geometry.contains_position(self.start):
            raise ValueError("path query start must lie within map bounds")
        if not self.map_geometry.contains_position(self.goal):
            raise ValueError("path query goal must lie within map bounds")


@dataclass(frozen=True, slots=True)
class Path:
    """One ordered same-layer waypoint path including its exact endpoints."""

    query: PathQuery
    waypoints: tuple[WorldPosition, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.query, PathQuery):
            raise ValueError("path requires a path query")
        if not isinstance(self.waypoints, tuple):
            raise ValueError("path waypoints must be an immutable tuple")
        if not self.waypoints:
            raise ValueError("path requires at least one waypoint")
        if any(not isinstance(waypoint, WorldPosition) for waypoint in self.waypoints):
            raise ValueError("path waypoints must be world positions")
        if self.waypoints[0] != self.query.start:
            raise ValueError("path must begin at the query start")
        if self.waypoints[-1] != self.query.goal:
            raise ValueError("path must end at the query goal")
        if self.query.start == self.query.goal and len(self.waypoints) != 1:
            raise ValueError("arrived path must contain exactly one waypoint")
        previous: WorldPosition | None = None
        for waypoint in self.waypoints:
            if waypoint.elevation != self.query.start.elevation:
                raise ValueError("path waypoints must share the query elevation layer")
            if not self.query.map_geometry.contains_position(waypoint):
                raise ValueError("path waypoints must lie within map bounds")
            if waypoint == previous:
                raise ValueError("path waypoints must not repeat consecutively")
            previous = waypoint


type PathQueryResult = PathQuery | PathQueryFailure


def prepare_path_query(
    map_geometry: MapGeometry | None,
    start: WorldPosition,
    goal: WorldPosition,
) -> PathQueryResult:
    """Validate deterministic path-query preconditions without finding a route."""
    if map_geometry is not None and not isinstance(map_geometry, MapGeometry):
        raise ValueError("path query map geometry must be map geometry or absent")
    if not isinstance(start, WorldPosition) or not isinstance(goal, WorldPosition):
        raise ValueError("path query endpoints must be world positions")
    if map_geometry is None:
        return PathQueryFailure(PathQueryCode.MISSING_MAP, "path query requires map geometry")
    if start.elevation != goal.elevation:
        return PathQueryFailure(
            PathQueryCode.ELEVATION_MISMATCH,
            "path query endpoints must share an elevation layer",
        )
    if not map_geometry.contains_position(start):
        return PathQueryFailure(
            PathQueryCode.START_OUTSIDE_MAP,
            "path query start must lie within map bounds",
        )
    if not map_geometry.contains_position(goal):
        return PathQueryFailure(
            PathQueryCode.GOAL_OUTSIDE_MAP,
            "path query goal must lie within map bounds",
        )
    return PathQuery(map_geometry, start, goal)
