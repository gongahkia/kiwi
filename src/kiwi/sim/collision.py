"""Exact integer collision predicates for operative discs and tactical geometry."""

from __future__ import annotations

from kiwi.domain.geometry import WorldPosition, WorldRectangle
from kiwi.sim.map_geometry import MapGeometry, MapObstacle

OPERATIVE_FOOTPRINT_RADIUS_MM = 350
OPERATIVE_SEPARATION_MM = OPERATIVE_FOOTPRINT_RADIUS_MM * 2

type _PlanarPoint = tuple[int, int]


def movement_segment_collides_map(
    start: WorldPosition,
    goal: WorldPosition,
    map_geometry: MapGeometry,
) -> bool:
    """Return whether a closed operative disc sweeps into map geometry."""
    if not isinstance(start, WorldPosition) or not isinstance(goal, WorldPosition):
        raise ValueError("movement collision endpoints must be world positions")
    if not isinstance(map_geometry, MapGeometry):
        raise ValueError("movement collision requires map geometry")
    if start.elevation != goal.elevation:
        raise ValueError("movement collision endpoints must share an elevation layer")
    if _position_collides_map(start, map_geometry) or _position_collides_map(goal, map_geometry):
        return True
    return any(
        _segment_within_obstacle_radius(start, goal, obstacle)
        for obstacle in map_geometry.obstacles
        if obstacle.elevation == start.elevation
    )


def movement_segments_violate_separation(
    first_start: WorldPosition,
    first_goal: WorldPosition,
    second_start: WorldPosition,
    second_goal: WorldPosition,
) -> bool:
    """Return whether two same-layer closed operative discs ever overlap."""
    positions = (first_start, first_goal, second_start, second_goal)
    if any(not isinstance(position, WorldPosition) for position in positions):
        raise ValueError("operative separation requires world positions")
    if first_start.elevation != first_goal.elevation:
        raise ValueError("first operative movement must remain on one elevation layer")
    if second_start.elevation != second_goal.elevation:
        raise ValueError("second operative movement must remain on one elevation layer")
    if first_start.elevation != second_start.elevation:
        return False
    first_segment = (_position_key(first_start), _position_key(first_goal))
    second_segment = (_position_key(second_start), _position_key(second_goal))
    if _segments_intersect(*first_segment, *second_segment):
        return True
    limit_squared = OPERATIVE_SEPARATION_MM * OPERATIVE_SEPARATION_MM
    return any(
        _point_within_segment_distance(point, segment_start, segment_goal, limit_squared)
        for point, segment_start, segment_goal in (
            (first_segment[0], *second_segment),
            (first_segment[1], *second_segment),
            (second_segment[0], *first_segment),
            (second_segment[1], *first_segment),
        )
    )


def _position_collides_map(position: WorldPosition, map_geometry: MapGeometry) -> bool:
    radius = OPERATIVE_FOOTPRINT_RADIUS_MM
    bounds = map_geometry.bounds
    if not (
        bounds.minimum_x.value + radius < position.x.value < bounds.maximum_x.value - radius
        and bounds.minimum_y.value + radius < position.y.value < bounds.maximum_y.value - radius
    ):
        return True
    return any(
        _point_within_rectangle_distance(position, obstacle.bounds, radius * radius)
        for obstacle in map_geometry.obstacles
        if obstacle.elevation == position.elevation
    )


def _segment_within_obstacle_radius(
    start: WorldPosition, goal: WorldPosition, obstacle: MapObstacle
) -> bool:
    rectangle = obstacle.bounds
    start_point = _position_key(start)
    goal_point = _position_key(goal)
    if _segment_intersects_rectangle(start_point, goal_point, rectangle):
        return True
    radius_squared = OPERATIVE_FOOTPRINT_RADIUS_MM * OPERATIVE_FOOTPRINT_RADIUS_MM
    if _point_within_rectangle_distance(start, rectangle, radius_squared):
        return True
    if _point_within_rectangle_distance(goal, rectangle, radius_squared):
        return True
    minimum_x = rectangle.minimum_x.value
    minimum_y = rectangle.minimum_y.value
    maximum_x = rectangle.maximum_x.value
    maximum_y = rectangle.maximum_y.value
    return any(
        _point_within_segment_distance(corner, start_point, goal_point, radius_squared)
        for corner in (
            (minimum_x, minimum_y),
            (minimum_x, maximum_y),
            (maximum_x, maximum_y),
            (maximum_x, minimum_y),
        )
    )


def _point_within_rectangle_distance(
    position: WorldPosition, rectangle: WorldRectangle, limit_squared: int
) -> bool:
    x = position.x.value
    y = position.y.value
    nearest_x = min(max(x, rectangle.minimum_x.value), rectangle.maximum_x.value)
    nearest_y = min(max(y, rectangle.minimum_y.value), rectangle.maximum_y.value)
    return (x - nearest_x) ** 2 + (y - nearest_y) ** 2 <= limit_squared


def _segment_intersects_rectangle(
    start: _PlanarPoint, goal: _PlanarPoint, rectangle: WorldRectangle
) -> bool:
    if _point_in_rectangle(start, rectangle) or _point_in_rectangle(goal, rectangle):
        return True
    minimum_x = rectangle.minimum_x.value
    minimum_y = rectangle.minimum_y.value
    maximum_x = rectangle.maximum_x.value
    maximum_y = rectangle.maximum_y.value
    corners = (
        (minimum_x, minimum_y),
        (minimum_x, maximum_y),
        (maximum_x, maximum_y),
        (maximum_x, minimum_y),
    )
    return any(
        _segments_intersect(start, goal, edge_start, edge_goal)
        for edge_start, edge_goal in zip(corners, corners[1:] + corners[:1], strict=True)
    )


def _point_in_rectangle(point: _PlanarPoint, rectangle: WorldRectangle) -> bool:
    return (
        rectangle.minimum_x.value <= point[0] <= rectangle.maximum_x.value
        and rectangle.minimum_y.value <= point[1] <= rectangle.maximum_y.value
    )


def _point_within_segment_distance(
    point: _PlanarPoint,
    start: _PlanarPoint,
    goal: _PlanarPoint,
    limit_squared: int,
) -> bool:
    dx = goal[0] - start[0]
    dy = goal[1] - start[1]
    length_squared = dx * dx + dy * dy
    if length_squared == 0:
        return (point[0] - start[0]) ** 2 + (point[1] - start[1]) ** 2 <= limit_squared
    projection = (point[0] - start[0]) * dx + (point[1] - start[1]) * dy
    if projection <= 0:
        return (point[0] - start[0]) ** 2 + (point[1] - start[1]) ** 2 <= limit_squared
    if projection >= length_squared:
        return (point[0] - goal[0]) ** 2 + (point[1] - goal[1]) ** 2 <= limit_squared
    cross = (point[0] - start[0]) * dy - (point[1] - start[1]) * dx
    return cross * cross <= limit_squared * length_squared


def _segments_intersect(
    first_start: _PlanarPoint,
    first_goal: _PlanarPoint,
    second_start: _PlanarPoint,
    second_goal: _PlanarPoint,
) -> bool:
    first_orientation = _orientation(first_start, first_goal, second_start)
    second_orientation = _orientation(first_start, first_goal, second_goal)
    third_orientation = _orientation(second_start, second_goal, first_start)
    fourth_orientation = _orientation(second_start, second_goal, first_goal)
    if first_orientation == 0 and _point_on_segment(second_start, first_start, first_goal):
        return True
    if second_orientation == 0 and _point_on_segment(second_goal, first_start, first_goal):
        return True
    if third_orientation == 0 and _point_on_segment(first_start, second_start, second_goal):
        return True
    if fourth_orientation == 0 and _point_on_segment(first_goal, second_start, second_goal):
        return True
    return (first_orientation > 0) != (second_orientation > 0) and (third_orientation > 0) != (
        fourth_orientation > 0
    )


def _orientation(start: _PlanarPoint, goal: _PlanarPoint, point: _PlanarPoint) -> int:
    return (goal[0] - start[0]) * (point[1] - start[1]) - (goal[1] - start[1]) * (
        point[0] - start[0]
    )


def _point_on_segment(point: _PlanarPoint, start: _PlanarPoint, goal: _PlanarPoint) -> bool:
    return min(start[0], goal[0]) <= point[0] <= max(start[0], goal[0]) and min(
        start[1], goal[1]
    ) <= point[1] <= max(start[1], goal[1])


def _position_key(position: WorldPosition) -> _PlanarPoint:
    return position.x.value, position.y.value
