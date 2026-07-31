"""Deterministic path-query values before a pathfinding algorithm is selected."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from heapq import heappop, heappush

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldSubunits
from kiwi.sim.map_geometry import MapGeometry, MapObstacle

OPERATIVE_FOOTPRINT_RADIUS_MM = 350
MAX_PATH_OBSTACLES = 64


class PathQueryCode(StrEnum):
    """Stable outcomes for path-query precondition validation."""

    MISSING_MAP = "P001_MISSING_MAP"
    ELEVATION_MISMATCH = "P002_ELEVATION_MISMATCH"
    START_OUTSIDE_MAP = "P003_START_OUTSIDE_MAP"
    GOAL_OUTSIDE_MAP = "P004_GOAL_OUTSIDE_MAP"


class PathSearchCode(StrEnum):
    """Stable outcomes for bounded deterministic pathfinding."""

    START_BLOCKED = "P005_START_BLOCKED"
    GOAL_BLOCKED = "P006_GOAL_BLOCKED"
    OBSTACLE_BUDGET_EXCEEDED = "P007_OBSTACLE_BUDGET_EXCEEDED"
    NO_ROUTE = "P008_NO_ROUTE"


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
class PathSearchFailure:
    """One structured bounded pathfinding failure."""

    code: PathSearchCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, PathSearchCode):
            raise ValueError("path search failure requires a path search code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("path search failure requires a non-empty message")


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
type PathSearchResult = Path | PathSearchFailure
type _PlanarPoint = tuple[int, int]
type _Bounds = tuple[int, int, int, int]
type _RouteKey = tuple[_PlanarPoint, ...]
type _Route = tuple[int, ...]


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


def find_path(query: PathQuery) -> PathSearchResult:
    """Find one bounded same-layer path with canonical Dijkstra tie-breaking."""
    if not isinstance(query, PathQuery):
        raise ValueError("pathfinding requires a path query")
    obstacles = tuple(
        obstacle
        for obstacle in query.map_geometry.obstacles
        if obstacle.elevation == query.start.elevation
    )
    if len(obstacles) > MAX_PATH_OBSTACLES:
        return PathSearchFailure(
            PathSearchCode.OBSTACLE_BUDGET_EXCEEDED,
            "path query exceeds the configured obstacle budget",
        )
    if not _point_is_clear(query.map_geometry, query.start, obstacles):
        return PathSearchFailure(
            PathSearchCode.START_BLOCKED,
            "path query start collides with map geometry",
        )
    if not _point_is_clear(query.map_geometry, query.goal, obstacles):
        return PathSearchFailure(
            PathSearchCode.GOAL_BLOCKED,
            "path query goal collides with map geometry",
        )
    if query.start == query.goal:
        return Path(query, (query.start,))
    nodes = _visibility_nodes(query, obstacles)
    adjacency = _visibility_graph(nodes, obstacles)
    route = _shortest_route(nodes, adjacency)
    if route is None:
        return PathSearchFailure(PathSearchCode.NO_ROUTE, "path query has no route")
    return Path(query, tuple(nodes[index] for index in route))


def _visibility_nodes(
    query: PathQuery, obstacles: tuple[MapObstacle, ...]
) -> tuple[WorldPosition, ...]:
    candidates: list[WorldPosition] = []
    clearance = OPERATIVE_FOOTPRINT_RADIUS_MM + 1
    for obstacle in obstacles:
        minimum_x = obstacle.bounds.minimum_x.value - clearance
        maximum_x = obstacle.bounds.maximum_x.value + clearance
        minimum_y = obstacle.bounds.minimum_y.value - clearance
        maximum_y = obstacle.bounds.maximum_y.value + clearance
        for x, y in (
            (minimum_x, minimum_y),
            (minimum_x, maximum_y),
            (maximum_x, minimum_y),
            (maximum_x, maximum_y),
        ):
            if not _coordinates_are_clear(
                query.map_geometry, x, y, query.start.elevation, obstacles
            ):
                continue
            candidate = WorldPosition(WorldSubunits(x), WorldSubunits(y), query.start.elevation)
            if candidate not in candidates and candidate not in (query.start, query.goal):
                candidates.append(candidate)
    candidates.sort(key=_position_key)
    return (query.start, *candidates, query.goal)


def _visibility_graph(
    nodes: tuple[WorldPosition, ...], obstacles: tuple[MapObstacle, ...]
) -> tuple[tuple[tuple[int, int], ...], ...]:
    adjacency: list[list[tuple[int, int]]] = [[] for _ in nodes]
    for left_index, left in enumerate(nodes):
        for right_index in range(left_index + 1, len(nodes)):
            right = nodes[right_index]
            if not _segment_is_clear(left, right, obstacles):
                continue
            cost = _manhattan_distance(left, right)
            adjacency[left_index].append((right_index, cost))
            adjacency[right_index].append((left_index, cost))
    for neighbours in adjacency:
        neighbours.sort(key=lambda entry: _position_key(nodes[entry[0]]))
    return tuple(tuple(neighbours) for neighbours in adjacency)


def _shortest_route(
    nodes: tuple[WorldPosition, ...],
    adjacency: tuple[tuple[tuple[int, int], ...], ...],
) -> _Route | None:
    start_key: _RouteKey = (_position_key(nodes[0]),)
    best: list[tuple[int, _RouteKey] | None] = [None] * len(nodes)
    best[0] = (0, start_key)
    open_nodes: list[tuple[int, _RouteKey, int, _Route]] = [(0, start_key, 0, (0,))]
    goal_index = len(nodes) - 1
    while open_nodes:
        cost, route_key, node_index, route = heappop(open_nodes)
        if best[node_index] != (cost, route_key):
            continue
        if node_index == goal_index:
            return route
        for neighbour_index, edge_cost in adjacency[node_index]:
            candidate_cost = cost + edge_cost
            candidate_key = route_key + (_position_key(nodes[neighbour_index]),)
            candidate = (candidate_cost, candidate_key)
            previous = best[neighbour_index]
            if previous is not None and candidate >= previous:
                continue
            best[neighbour_index] = candidate
            heappush(
                open_nodes,
                (
                    candidate_cost,
                    candidate_key,
                    neighbour_index,
                    route + (neighbour_index,),
                ),
            )
    return None


def _point_is_clear(
    map_geometry: MapGeometry,
    position: WorldPosition,
    obstacles: tuple[MapObstacle, ...],
) -> bool:
    return _coordinates_are_clear(
        map_geometry,
        position.x.value,
        position.y.value,
        position.elevation,
        obstacles,
    )


def _coordinates_are_clear(
    map_geometry: MapGeometry,
    x: int,
    y: int,
    elevation: ElevationLayer,
    obstacles: tuple[MapObstacle, ...],
) -> bool:
    clearance = OPERATIVE_FOOTPRINT_RADIUS_MM
    bounds = map_geometry.bounds
    if not (
        bounds.minimum_x.value + clearance < x < bounds.maximum_x.value - clearance
        and bounds.minimum_y.value + clearance < y < bounds.maximum_y.value - clearance
    ):
        return False
    return not any(
        _point_in_bounds(x, y, _inflated_bounds(obstacle, clearance))
        for obstacle in obstacles
        if obstacle.elevation == elevation
    )


def _segment_is_clear(
    start: WorldPosition,
    goal: WorldPosition,
    obstacles: tuple[MapObstacle, ...],
) -> bool:
    return not any(
        _segment_intersects_bounds(
            start, goal, _inflated_bounds(obstacle, OPERATIVE_FOOTPRINT_RADIUS_MM)
        )
        for obstacle in obstacles
    )


def _inflated_bounds(obstacle: MapObstacle, clearance: int) -> _Bounds:
    return (
        obstacle.bounds.minimum_x.value - clearance,
        obstacle.bounds.minimum_y.value - clearance,
        obstacle.bounds.maximum_x.value + clearance,
        obstacle.bounds.maximum_y.value + clearance,
    )


def _segment_intersects_bounds(start: WorldPosition, goal: WorldPosition, bounds: _Bounds) -> bool:
    start_point = _position_key(start)
    goal_point = _position_key(goal)
    if _point_in_bounds(*start_point, bounds) or _point_in_bounds(*goal_point, bounds):
        return True
    minimum_x, minimum_y, maximum_x, maximum_y = bounds
    corners = (
        (minimum_x, minimum_y),
        (minimum_x, maximum_y),
        (maximum_x, maximum_y),
        (maximum_x, minimum_y),
    )
    return any(
        _segments_intersect(start_point, goal_point, edge_start, edge_end)
        for edge_start, edge_end in zip(corners, corners[1:] + corners[:1], strict=True)
    )


def _point_in_bounds(x: int, y: int, bounds: _Bounds) -> bool:
    minimum_x, minimum_y, maximum_x, maximum_y = bounds
    return minimum_x <= x <= maximum_x and minimum_y <= y <= maximum_y


def _segments_intersect(
    first_start: _PlanarPoint,
    first_end: _PlanarPoint,
    second_start: _PlanarPoint,
    second_end: _PlanarPoint,
) -> bool:
    first_orientation = _orientation(first_start, first_end, second_start)
    second_orientation = _orientation(first_start, first_end, second_end)
    third_orientation = _orientation(second_start, second_end, first_start)
    fourth_orientation = _orientation(second_start, second_end, first_end)
    if first_orientation == 0 and _point_on_segment(second_start, first_start, first_end):
        return True
    if second_orientation == 0 and _point_on_segment(second_end, first_start, first_end):
        return True
    if third_orientation == 0 and _point_on_segment(first_start, second_start, second_end):
        return True
    if fourth_orientation == 0 and _point_on_segment(first_end, second_start, second_end):
        return True
    return (first_orientation > 0) != (second_orientation > 0) and (third_orientation > 0) != (
        fourth_orientation > 0
    )


def _orientation(start: _PlanarPoint, end: _PlanarPoint, point: _PlanarPoint) -> int:
    return (end[0] - start[0]) * (point[1] - start[1]) - (end[1] - start[1]) * (point[0] - start[0])


def _point_on_segment(point: _PlanarPoint, start: _PlanarPoint, end: _PlanarPoint) -> bool:
    return min(start[0], end[0]) <= point[0] <= max(start[0], end[0]) and min(
        start[1], end[1]
    ) <= point[1] <= max(start[1], end[1])


def _manhattan_distance(start: WorldPosition, goal: WorldPosition) -> int:
    return abs(goal.x.value - start.x.value) + abs(goal.y.value - start.y.value)


def _position_key(position: WorldPosition) -> _PlanarPoint:
    return position.x.value, position.y.value
