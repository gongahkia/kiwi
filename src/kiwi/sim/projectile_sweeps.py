"""Bounded deterministic swept collision queries for live point projectiles."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.geometry import (
    WorldPosition,
    WorldRectangle,
    WorldSubunits,
    round_nearest_ties_away_from_zero,
    segment_intersects_closed_rectangle,
    translate,
)
from kiwi.domain.ids import CoverId, EntityId, ObstacleId, ProjectileId
from kiwi.sim.collision import OPERATIVE_FOOTPRINT_RADIUS_MM
from kiwi.sim.projectiles import Projectile
from kiwi.sim.state import MissionState

PROJECTILE_SWEEP_TIME_SUBTICKS = 1 << 32

type ProjectileCollisionTargetId = ObstacleId | CoverId | EntityId


class ProjectileCollisionKind(StrEnum):
    """Stable collision-class precedence for equal swept times."""

    OBSTACLE = "obstacle"
    COVER = "cover"
    OPERATIVE = "operative"


_COLLISION_PRECEDENCE = {
    ProjectileCollisionKind.OBSTACLE: 0,
    ProjectileCollisionKind.COVER: 1,
    ProjectileCollisionKind.OPERATIVE: 2,
}


@dataclass(frozen=True, slots=True)
class ProjectileCollision:
    """One first collision on a bounded projectile sweep."""

    kind: ProjectileCollisionKind
    target_id: ProjectileCollisionTargetId
    subtick: int
    position: WorldPosition

    def __post_init__(self) -> None:
        if not isinstance(self.kind, ProjectileCollisionKind):
            raise ValueError("projectile collision requires a collision kind")
        expected_type = {
            ProjectileCollisionKind.OBSTACLE: ObstacleId,
            ProjectileCollisionKind.COVER: CoverId,
            ProjectileCollisionKind.OPERATIVE: EntityId,
        }[self.kind]
        if not isinstance(self.target_id, expected_type):
            raise ValueError("projectile collision target does not match its kind")
        if not isinstance(self.subtick, int) or isinstance(self.subtick, bool):
            raise ValueError("projectile collision subtick must be an integer")
        if not 0 <= self.subtick <= PROJECTILE_SWEEP_TIME_SUBTICKS:
            raise ValueError("projectile collision subtick is outside the sweep")
        if not isinstance(self.position, WorldPosition):
            raise ValueError("projectile collision requires a world position")


@dataclass(frozen=True, slots=True)
class ProjectileSweep:
    """One projectile's start, intended endpoint, and optional first collision."""

    projectile_id: ProjectileId
    start_position: WorldPosition
    end_position: WorldPosition
    collision: ProjectileCollision | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.projectile_id, ProjectileId):
            raise ValueError("projectile sweep requires a projectile ID")
        if not isinstance(self.start_position, WorldPosition):
            raise ValueError("projectile sweep requires a start position")
        if not isinstance(self.end_position, WorldPosition):
            raise ValueError("projectile sweep requires an end position")
        if self.end_position.elevation != self.start_position.elevation:
            raise ValueError("projectile sweep endpoints must share an elevation")
        if self.collision is not None:
            if not isinstance(self.collision, ProjectileCollision):
                raise ValueError("projectile sweep collision must be a projectile collision")
            if self.collision.position.elevation != self.start_position.elevation:
                raise ValueError("projectile collision must share its sweep elevation")


def sweep_projectiles(state: MissionState) -> tuple[ProjectileSweep, ...]:
    """Return projectile-ID-ordered swept paths without applying impact effects."""
    if not isinstance(state, MissionState):
        raise ValueError("projectile sweep requires mission state")
    return tuple(_sweep_projectile(projectile, state) for projectile in state.projectiles.entries)


def _sweep_projectile(projectile: Projectile, state: MissionState) -> ProjectileSweep:
    start = projectile.position
    end = translate(start, projectile.velocity)
    candidates = _collision_candidates(projectile, start, end, state)
    if not candidates:
        return ProjectileSweep(projectile.projectile_id, start, end)
    subtick, kind, target_id = min(candidates, key=_candidate_key)
    return ProjectileSweep(
        projectile.projectile_id,
        start,
        end,
        ProjectileCollision(kind, target_id, subtick, _position_at(start, end, subtick)),
    )


def _collision_candidates(
    projectile: Projectile, start: WorldPosition, end: WorldPosition, state: MissionState
) -> tuple[tuple[int, ProjectileCollisionKind, ProjectileCollisionTargetId], ...]:
    candidates: list[tuple[int, ProjectileCollisionKind, ProjectileCollisionTargetId]] = []
    if state.map_geometry is not None:
        for obstacle in state.map_geometry.obstacles:
            if obstacle.elevation != start.elevation:
                continue
            subtick = _first_intersection_subtick(
                start,
                end,
                _rectangle_prefix_predicate(start, obstacle.bounds),
            )
            if subtick is not None:
                candidates.append((subtick, ProjectileCollisionKind.OBSTACLE, obstacle.obstacle_id))
    for cover in state.covers.segments:
        if cover.start.elevation != start.elevation:
            continue
        subtick = _first_intersection_subtick(
            start,
            end,
            _cover_prefix_predicate(start, cover.start, cover.end),
        )
        if subtick is not None:
            candidates.append((subtick, ProjectileCollisionKind.COVER, cover.cover_id))
    for entity in state.entities:
        if entity.entity_id == projectile.owner_entity_id:
            continue
        if entity.position.elevation != start.elevation:
            continue
        subtick = _first_intersection_subtick(
            start,
            end,
            _operative_prefix_predicate(start, entity.position),
        )
        if subtick is not None:
            candidates.append((subtick, ProjectileCollisionKind.OPERATIVE, entity.entity_id))
    return tuple(candidates)


def _rectangle_prefix_predicate(
    start: WorldPosition, bounds: WorldRectangle
) -> Callable[[WorldPosition], bool]:
    def intersects(prefix_end: WorldPosition) -> bool:
        return segment_intersects_closed_rectangle(start, prefix_end, bounds)

    return intersects


def _cover_prefix_predicate(
    start: WorldPosition, cover_start: WorldPosition, cover_end: WorldPosition
) -> Callable[[WorldPosition], bool]:
    def intersects(prefix_end: WorldPosition) -> bool:
        return _segments_intersect(start, prefix_end, cover_start, cover_end)

    return intersects


def _operative_prefix_predicate(
    start: WorldPosition, center: WorldPosition
) -> Callable[[WorldPosition], bool]:
    def intersects(prefix_end: WorldPosition) -> bool:
        return _segment_intersects_disc(start, prefix_end, center)

    return intersects


def _first_intersection_subtick(
    start: WorldPosition,
    end: WorldPosition,
    intersects_prefix: Callable[[WorldPosition], bool],
) -> int | None:
    if intersects_prefix(start):
        return 0
    if not intersects_prefix(end):
        return None
    lower = 0
    upper = PROJECTILE_SWEEP_TIME_SUBTICKS
    while upper - lower > 1:
        middle = (lower + upper) // 2
        if intersects_prefix(_position_at(start, end, middle)):
            upper = middle
        else:
            lower = middle
    return upper


def _candidate_key(
    candidate: tuple[int, ProjectileCollisionKind, ProjectileCollisionTargetId],
) -> tuple[int, int, int]:
    subtick, kind, target_id = candidate
    return subtick, _COLLISION_PRECEDENCE[kind], target_id.value


def _position_at(start: WorldPosition, end: WorldPosition, subtick: int) -> WorldPosition:
    return WorldPosition(
        WorldSubunits(
            start.x.value
            + round_nearest_ties_away_from_zero(
                (end.x.value - start.x.value) * subtick, PROJECTILE_SWEEP_TIME_SUBTICKS
            )
        ),
        WorldSubunits(
            start.y.value
            + round_nearest_ties_away_from_zero(
                (end.y.value - start.y.value) * subtick, PROJECTILE_SWEEP_TIME_SUBTICKS
            )
        ),
        start.elevation,
    )


def _segment_intersects_disc(
    start: WorldPosition, end: WorldPosition, center: WorldPosition
) -> bool:
    if center.elevation != start.elevation:
        return False
    dx = end.x.value - start.x.value
    dy = end.y.value - start.y.value
    offset_x = center.x.value - start.x.value
    offset_y = center.y.value - start.y.value
    length_squared = dx * dx + dy * dy
    if length_squared == 0:
        nearest_x = start.x.value
        nearest_y = start.y.value
    else:
        numerator = offset_x * dx + offset_y * dy
        if numerator <= 0:
            nearest_x = start.x.value
            nearest_y = start.y.value
        elif numerator >= length_squared:
            nearest_x = end.x.value
            nearest_y = end.y.value
        else:
            nearest_x_numerator = start.x.value * length_squared + dx * numerator
            nearest_y_numerator = start.y.value * length_squared + dy * numerator
            distance_x_numerator = center.x.value * length_squared - nearest_x_numerator
            distance_y_numerator = center.y.value * length_squared - nearest_y_numerator
            return (
                distance_x_numerator * distance_x_numerator
                + distance_y_numerator * distance_y_numerator
                <= (OPERATIVE_FOOTPRINT_RADIUS_MM * length_squared) ** 2
            )
    return (center.x.value - nearest_x) ** 2 + (
        center.y.value - nearest_y
    ) ** 2 <= OPERATIVE_FOOTPRINT_RADIUS_MM**2


def _segments_intersect(
    first_start: WorldPosition,
    first_end: WorldPosition,
    second_start: WorldPosition,
    second_end: WorldPosition,
) -> bool:
    first = (first_start.x.value, first_start.y.value)
    first_end_key = (first_end.x.value, first_end.y.value)
    second = (second_start.x.value, second_start.y.value)
    second_end_key = (second_end.x.value, second_end.y.value)
    return _segments_intersect_keys(first, first_end_key, second, second_end_key)


def _segments_intersect_keys(
    first_start: tuple[int, int],
    first_end: tuple[int, int],
    second_start: tuple[int, int],
    second_end: tuple[int, int],
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


def _orientation(start: tuple[int, int], end: tuple[int, int], point: tuple[int, int]) -> int:
    return (end[0] - start[0]) * (point[1] - start[1]) - (end[1] - start[1]) * (point[0] - start[0])


def _point_on_segment(point: tuple[int, int], start: tuple[int, int], end: tuple[int, int]) -> bool:
    return min(start[0], end[0]) <= point[0] <= max(start[0], end[0]) and min(
        start[1], end[1]
    ) <= point[1] <= max(start[1], end[1])
