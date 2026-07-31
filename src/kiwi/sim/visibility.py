"""Deterministic line-of-sight queries over canonical map geometry."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.geometry import (
    WorldPosition,
    WorldRectangle,
    WorldSubunits,
    segment_intersects_closed_rectangle,
)
from kiwi.domain.ids import ObstacleId
from kiwi.sim.map_geometry import MapGeometry


class VisibilityQueryCode(StrEnum):
    """Stable precondition failures for visibility queries."""

    MISSING_MAP = "V001_MISSING_MAP"
    OBSERVER_OUTSIDE_MAP = "V002_OBSERVER_OUTSIDE_MAP"
    TARGET_OUTSIDE_MAP = "V003_TARGET_OUTSIDE_MAP"


class VisibilityStatus(StrEnum):
    """The exact reason a valid visibility query is or is not visible."""

    VISIBLE = "visible"
    RANGE_BLOCKED = "range_blocked"
    ELEVATION_BLOCKED = "elevation_blocked"
    OBSTACLE_BLOCKED = "obstacle_blocked"


@dataclass(frozen=True, slots=True)
class SensorRange:
    """One exact non-negative planar sensing radius in canonical millimetres."""

    maximum_distance: WorldSubunits

    def __post_init__(self) -> None:
        if not isinstance(self.maximum_distance, WorldSubunits):
            raise ValueError("sensor range requires world subunits")
        if self.maximum_distance.value < 0:
            raise ValueError("sensor range must be non-negative")


@dataclass(frozen=True, slots=True)
class VisibleObstacle:
    """One same-layer obstacle projection visible to an observer sensor."""

    obstacle_id: ObstacleId
    bounds: WorldRectangle

    def __post_init__(self) -> None:
        if not isinstance(self.obstacle_id, ObstacleId):
            raise ValueError("visible obstacle requires an obstacle ID")
        if not isinstance(self.bounds, WorldRectangle):
            raise ValueError("visible obstacle requires world rectangle bounds")


@dataclass(frozen=True, slots=True)
class VisibleGeometry:
    """An obstacle-ID-ordered range-visible geometry projection."""

    observer: WorldPosition
    sensor_range: SensorRange
    obstacles: tuple[VisibleObstacle, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.observer, WorldPosition):
            raise ValueError("visible geometry requires an observer position")
        if not isinstance(self.sensor_range, SensorRange):
            raise ValueError("visible geometry requires a sensor range")
        if not isinstance(self.obstacles, tuple):
            raise ValueError("visible geometry obstacles must be an immutable tuple")
        previous_id = 0
        for obstacle in self.obstacles:
            if not isinstance(obstacle, VisibleObstacle):
                raise ValueError("visible geometry obstacles must be visible obstacles")
            if obstacle.obstacle_id.value <= previous_id:
                raise ValueError("visible geometry obstacles must be obstacle-ID ordered")
            previous_id = obstacle.obstacle_id.value


@dataclass(frozen=True, slots=True)
class VisibilityQueryFailure:
    """One structured invalid visibility-query result."""

    code: VisibilityQueryCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, VisibilityQueryCode):
            raise ValueError("visibility query failure requires a visibility query code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("visibility query failure requires a non-empty message")


@dataclass(frozen=True, slots=True)
class VisibilityQuery:
    """One immutable observer-to-target query over one bounded map."""

    map_geometry: MapGeometry
    observer: WorldPosition
    target: WorldPosition
    sensor_range: SensorRange

    def __post_init__(self) -> None:
        if not isinstance(self.map_geometry, MapGeometry):
            raise ValueError("visibility query requires map geometry")
        if not isinstance(self.observer, WorldPosition) or not isinstance(
            self.target, WorldPosition
        ):
            raise ValueError("visibility query endpoints must be world positions")
        if not isinstance(self.sensor_range, SensorRange):
            raise ValueError("visibility query requires a sensor range")
        if not self.map_geometry.contains_position(self.observer):
            raise ValueError("visibility query observer must lie within map bounds")
        if not self.map_geometry.contains_position(self.target):
            raise ValueError("visibility query target must lie within map bounds")


@dataclass(frozen=True, slots=True)
class VisibilityResult:
    """One deterministic visibility result and optional canonical obstacle blocker."""

    query: VisibilityQuery
    status: VisibilityStatus
    blocking_obstacle_id: ObstacleId | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.query, VisibilityQuery):
            raise ValueError("visibility result requires a visibility query")
        if not isinstance(self.status, VisibilityStatus):
            raise ValueError("visibility result requires a visibility status")
        if self.status is VisibilityStatus.OBSTACLE_BLOCKED:
            if not isinstance(self.blocking_obstacle_id, ObstacleId):
                raise ValueError("obstacle-blocked visibility requires an obstacle ID")
            if not any(
                obstacle.obstacle_id == self.blocking_obstacle_id
                and obstacle.elevation == self.query.observer.elevation
                for obstacle in self.query.map_geometry.obstacles
            ):
                raise ValueError("visibility blocker must be a same-layer map obstacle")
            obstacle = next(
                obstacle
                for obstacle in self.query.map_geometry.obstacles
                if obstacle.obstacle_id == self.blocking_obstacle_id
            )
            if not segment_intersects_closed_rectangle(
                self.query.observer,
                self.query.target,
                obstacle.bounds,
            ):
                raise ValueError("visibility blocker must intersect the query segment")
            return
        if self.blocking_obstacle_id is not None:
            raise ValueError("non-obstacle visibility results cannot retain a blocker")


type VisibilityQueryResult = VisibilityQuery | VisibilityQueryFailure


def prepare_visibility_query(
    map_geometry: MapGeometry | None,
    observer: WorldPosition,
    target: WorldPosition,
    sensor_range: SensorRange,
) -> VisibilityQueryResult:
    """Validate a bounded visibility query before authoritative resolution."""
    if map_geometry is not None and not isinstance(map_geometry, MapGeometry):
        raise ValueError("visibility query map geometry must be map geometry or absent")
    if not isinstance(observer, WorldPosition) or not isinstance(target, WorldPosition):
        raise ValueError("visibility query endpoints must be world positions")
    if not isinstance(sensor_range, SensorRange):
        raise ValueError("visibility query requires a sensor range")
    if map_geometry is None:
        return VisibilityQueryFailure(
            VisibilityQueryCode.MISSING_MAP,
            "visibility query requires map geometry",
        )
    if not map_geometry.contains_position(observer):
        return VisibilityQueryFailure(
            VisibilityQueryCode.OBSERVER_OUTSIDE_MAP,
            "visibility query observer must lie within map bounds",
        )
    if not map_geometry.contains_position(target):
        return VisibilityQueryFailure(
            VisibilityQueryCode.TARGET_OUTSIDE_MAP,
            "visibility query target must lie within map bounds",
        )
    return VisibilityQuery(map_geometry, observer, target, sensor_range)


def resolve_visibility(query: VisibilityQuery) -> VisibilityResult:
    """Resolve exact same-layer line of sight with canonical obstacle priority."""
    if not isinstance(query, VisibilityQuery):
        raise ValueError("visibility resolution requires a visibility query")
    if not _is_within_sensor_range(query.observer, query.target, query.sensor_range):
        return VisibilityResult(query, VisibilityStatus.RANGE_BLOCKED)
    if query.observer.elevation != query.target.elevation:
        return VisibilityResult(query, VisibilityStatus.ELEVATION_BLOCKED)
    for obstacle in query.map_geometry.obstacles:
        if obstacle.elevation != query.observer.elevation:
            continue
        if segment_intersects_closed_rectangle(query.observer, query.target, obstacle.bounds):
            return VisibilityResult(
                query,
                VisibilityStatus.OBSTACLE_BLOCKED,
                obstacle.obstacle_id,
            )
    return VisibilityResult(query, VisibilityStatus.VISIBLE)


def visible_geometry(
    map_geometry: MapGeometry | None,
    observer: WorldPosition,
    sensor_range: SensorRange,
) -> VisibleGeometry | VisibilityQueryFailure:
    """Project same-layer obstacles whose nearest point is within sensor range."""
    if map_geometry is not None and not isinstance(map_geometry, MapGeometry):
        raise ValueError("visible geometry map must be map geometry or absent")
    if not isinstance(observer, WorldPosition):
        raise ValueError("visible geometry observer must be a world position")
    if not isinstance(sensor_range, SensorRange):
        raise ValueError("visible geometry requires a sensor range")
    if map_geometry is None:
        return VisibilityQueryFailure(
            VisibilityQueryCode.MISSING_MAP,
            "visible geometry requires map geometry",
        )
    if not map_geometry.contains_position(observer):
        return VisibilityQueryFailure(
            VisibilityQueryCode.OBSERVER_OUTSIDE_MAP,
            "visible geometry observer must lie within map bounds",
        )
    obstacles = tuple(
        VisibleObstacle(obstacle.obstacle_id, obstacle.bounds)
        for obstacle in map_geometry.obstacles
        if obstacle.elevation == observer.elevation
        and _rectangle_is_within_sensor_range(observer, obstacle.bounds, sensor_range)
    )
    return VisibleGeometry(observer, sensor_range, obstacles)


def _is_within_sensor_range(
    observer: WorldPosition,
    target: WorldPosition,
    sensor_range: SensorRange,
) -> bool:
    distance_x = target.x.value - observer.x.value
    distance_y = target.y.value - observer.y.value
    return (
        distance_x * distance_x + distance_y * distance_y
        <= sensor_range.maximum_distance.value * sensor_range.maximum_distance.value
    )


def _rectangle_is_within_sensor_range(
    observer: WorldPosition,
    rectangle: WorldRectangle,
    sensor_range: SensorRange,
) -> bool:
    nearest_x = min(max(observer.x.value, rectangle.minimum_x.value), rectangle.maximum_x.value)
    nearest_y = min(max(observer.y.value, rectangle.minimum_y.value), rectangle.maximum_y.value)
    distance_x = observer.x.value - nearest_x
    distance_y = observer.y.value - nearest_y
    return (
        distance_x * distance_x + distance_y * distance_y
        <= sensor_range.maximum_distance.value * sensor_range.maximum_distance.value
    )
