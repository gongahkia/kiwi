"""Deterministic suppression from projectile paths and collision impacts."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.domain.geometry import WorldPosition, translate
from kiwi.domain.ids import EntityId, IdKind
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.projectile_impacts import ProjectileImpact
from kiwi.sim.projectile_sweeps import ProjectileCollisionKind
from kiwi.sim.projectiles import Projectile, ProjectileStore
from kiwi.sim.state import MissionState
from kiwi.sim.weapons import MAX_AIM_QUALITY_BASIS_POINTS, MAX_SUPPRESSION_BASIS_POINTS

NEAR_MISS_RADIUS_MM = 2_000
IMPACT_SUPPRESSION_RADIUS_MM = 3_000
NEAR_MISS_SUPPRESSION_BASIS_POINTS = 1_500
IMPACT_SUPPRESSION_BASIS_POINTS = 2_500
SUPPRESSION_DECAY_PER_TICK_BASIS_POINTS = 500


class SuppressionSourceKind(StrEnum):
    """The closed physical cause of one suppression contribution."""

    NEAR_MISS = "near_miss"
    IMPACT = "impact"


@dataclass(frozen=True, slots=True)
class SuppressionContribution:
    """One source-retaining projectile-path or impact contribution."""

    target_entity_id: EntityId
    source_kind: SuppressionSourceKind
    projectile: Projectile
    impact: ProjectileImpact | None
    basis_points: int

    def __post_init__(self) -> None:
        if not isinstance(self.target_entity_id, EntityId):
            raise ValueError("suppression contribution requires a target entity ID")
        if not isinstance(self.source_kind, SuppressionSourceKind):
            raise ValueError("suppression contribution requires a source kind")
        if not isinstance(self.projectile, Projectile):
            raise ValueError("suppression contribution requires a projectile")
        if self.impact is not None:
            if not isinstance(self.impact, ProjectileImpact):
                raise ValueError("suppression contribution impact must be a projectile impact")
            if self.impact.projectile != self.projectile:
                raise ValueError("suppression contribution impact must retain its projectile")
        if not isinstance(self.basis_points, int) or isinstance(self.basis_points, bool):
            raise ValueError("suppression contribution must use integer basis points")
        expected_basis_points = {
            SuppressionSourceKind.NEAR_MISS: NEAR_MISS_SUPPRESSION_BASIS_POINTS,
            SuppressionSourceKind.IMPACT: IMPACT_SUPPRESSION_BASIS_POINTS,
        }[self.source_kind]
        if self.basis_points != expected_basis_points:
            raise ValueError("suppression contribution basis points must match its source kind")
        if self.source_kind is SuppressionSourceKind.IMPACT and self.impact is None:
            raise ValueError("impact suppression requires a projectile impact")


@dataclass(frozen=True, slots=True)
class SuppressionResolution:
    """One entity's decayed, contributed, and aim-clamped suppression successor."""

    tick: int
    entity_id: EntityId
    suppression_before: int
    decay_basis_points: int
    contributions: tuple[SuppressionContribution, ...]
    suppression_after: int
    aim_before: int
    aim_ceiling_after: int
    aim_after: int

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("suppression resolution tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError(
                "suppression resolution tick must fit non-negative signed 64-bit range"
            )
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("suppression resolution requires an entity ID")
        values = (
            self.suppression_before,
            self.decay_basis_points,
            self.suppression_after,
            self.aim_before,
            self.aim_ceiling_after,
            self.aim_after,
        )
        if any(not isinstance(value, int) or isinstance(value, bool) for value in values):
            raise ValueError("suppression resolution values must be integers")
        if not 0 <= self.suppression_before <= MAX_SUPPRESSION_BASIS_POINTS:
            raise ValueError(
                "suppression resolution prior suppression is outside the configured range"
            )
        if self.decay_basis_points != min(
            self.suppression_before, SUPPRESSION_DECAY_PER_TICK_BASIS_POINTS
        ):
            raise ValueError("suppression resolution decay is invalid")
        if not isinstance(self.contributions, tuple):
            raise ValueError("suppression resolution contributions must be immutable")
        previous_key = (0, -1)
        contribution_total = 0
        for contribution in self.contributions:
            if not isinstance(contribution, SuppressionContribution):
                raise ValueError("suppression resolution requires suppression contributions")
            if contribution.target_entity_id != self.entity_id:
                raise ValueError("suppression contribution target must match its resolution")
            key = (
                contribution.projectile.projectile_id.value,
                0 if contribution.source_kind is SuppressionSourceKind.NEAR_MISS else 1,
            )
            if key <= previous_key:
                raise ValueError("suppression contributions must be canonically ordered")
            previous_key = key
            contribution_total += contribution.basis_points
        expected_suppression = min(
            MAX_SUPPRESSION_BASIS_POINTS,
            self.suppression_before - self.decay_basis_points + contribution_total,
        )
        if self.suppression_after != expected_suppression:
            raise ValueError("suppression resolution successor is invalid")
        if not 0 <= self.aim_before <= MAX_AIM_QUALITY_BASIS_POINTS:
            raise ValueError("suppression resolution prior aim is outside the configured range")
        if self.aim_ceiling_after != MAX_AIM_QUALITY_BASIS_POINTS - self.suppression_after:
            raise ValueError("suppression resolution aim ceiling must match suppression")
        if self.aim_after != min(self.aim_before, self.aim_ceiling_after):
            raise ValueError("suppression resolution aim successor must clamp immediately")


@dataclass(frozen=True, slots=True)
class SuppressionPhase:
    """One state successor and entity-ID-ordered suppression results."""

    state: MissionState
    resolutions: tuple[SuppressionResolution, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("suppression phase requires mission state")
        if not isinstance(self.resolutions, tuple):
            raise ValueError("suppression phase resolutions must be immutable")
        if any(
            not isinstance(resolution, SuppressionResolution) for resolution in self.resolutions
        ):
            raise ValueError("suppression phase must contain suppression resolutions")
        entity_ids = tuple(entity.entity_id for entity in self.state.entities)
        if tuple(resolution.entity_id for resolution in self.resolutions) != entity_ids:
            raise ValueError("suppression resolutions must cover every mission entity")
        for resolution in self.resolutions:
            if resolution.tick != self.state.tick:
                raise ValueError("suppression resolutions must share the state tick")
            if (
                self.state.suppressions.suppression_for(resolution.entity_id)
                != resolution.suppression_after
            ):
                raise ValueError("suppression phase state must retain resolved suppression")
            if self.state.aim_states.quality_for(resolution.entity_id) != resolution.aim_after:
                raise ValueError("suppression phase state must retain resolved aim")


def resolve_projectile_suppression(
    state: MissionState,
    source_projectiles: tuple[Projectile, ...],
    impacts: tuple[ProjectileImpact, ...],
) -> SuppressionPhase:
    """Decay and resolve path and impact suppression from this active tick's shots."""
    if not isinstance(state, MissionState):
        raise ValueError("suppression resolution requires mission state")
    if not isinstance(source_projectiles, tuple):
        raise ValueError("suppression resolution requires immutable source projectiles")
    if not isinstance(impacts, tuple):
        raise ValueError("suppression resolution requires immutable projectile impacts")
    sources = ProjectileStore(source_projectiles)
    _validate_source_projectiles(state, sources)
    source_impacts = _source_impacts(state, sources, impacts)
    contributions_by_entity: list[list[SuppressionContribution]] = [[] for _ in state.entities]
    for projectile, impact in zip(sources.entries, source_impacts, strict=True):
        path_end = (
            impact.collision.position
            if impact is not None
            else translate(projectile.position, projectile.velocity)
        )
        direct_target_id = _direct_operative_target(impact)
        for index, entity in enumerate(state.entities):
            if entity.entity_id in (projectile.owner_entity_id, direct_target_id):
                continue
            if _is_within_segment_radius(
                entity.position, projectile.position, path_end, NEAR_MISS_RADIUS_MM
            ):
                contributions_by_entity[index].append(
                    SuppressionContribution(
                        entity.entity_id,
                        SuppressionSourceKind.NEAR_MISS,
                        projectile,
                        impact,
                        NEAR_MISS_SUPPRESSION_BASIS_POINTS,
                    )
                )
        if impact is None:
            continue
        for index, entity in enumerate(state.entities):
            if entity.entity_id == projectile.owner_entity_id:
                continue
            if _is_within_point_radius(
                entity.position, impact.collision.position, IMPACT_SUPPRESSION_RADIUS_MM
            ):
                contributions_by_entity[index].append(
                    SuppressionContribution(
                        entity.entity_id,
                        SuppressionSourceKind.IMPACT,
                        projectile,
                        impact,
                        IMPACT_SUPPRESSION_BASIS_POINTS,
                    )
                )
    suppressions = state.suppressions
    aim_states = state.aim_states
    resolutions: list[SuppressionResolution] = []
    for entity, contributions in zip(state.entities, contributions_by_entity, strict=True):
        entity_id = entity.entity_id
        suppression_before = suppressions.suppression_for(entity_id)
        decay_basis_points = min(suppression_before, SUPPRESSION_DECAY_PER_TICK_BASIS_POINTS)
        suppression_after = min(
            MAX_SUPPRESSION_BASIS_POINTS,
            suppression_before
            - decay_basis_points
            + sum(contribution.basis_points for contribution in contributions),
        )
        aim_before = aim_states.quality_for(entity_id)
        aim_ceiling_after = MAX_AIM_QUALITY_BASIS_POINTS - suppression_after
        aim_after = min(aim_before, aim_ceiling_after)
        resolution = SuppressionResolution(
            state.tick,
            entity_id,
            suppression_before,
            decay_basis_points,
            tuple(contributions),
            suppression_after,
            aim_before,
            aim_ceiling_after,
            aim_after,
        )
        suppressions = suppressions.with_suppression(entity_id, suppression_after)
        aim_states = aim_states.with_quality(entity_id, aim_after)
        resolutions.append(resolution)
    return SuppressionPhase(
        replace(state, suppressions=suppressions, aim_states=aim_states),
        tuple(resolutions),
    )


def _validate_source_projectiles(state: MissionState, sources: ProjectileStore) -> None:
    entity_ids = tuple(entity.entity_id for entity in state.entities)
    next_projectile_id = state.id_allocator.next_ids[int(IdKind.PROJECTILE)]
    next_intention_id = state.id_allocator.next_ids[int(IdKind.INTENTION)]
    for projectile in sources.entries:
        if projectile.owner_entity_id not in entity_ids:
            raise ValueError("suppression source projectiles must belong to mission entities")
        if projectile.projectile_id.value >= next_projectile_id:
            raise ValueError("suppression source projectile IDs must be allocated")
        if projectile.source_intention_id.value >= next_intention_id:
            raise ValueError("suppression source intention IDs must be allocated")


def _source_impacts(
    state: MissionState,
    sources: ProjectileStore,
    impacts: tuple[ProjectileImpact, ...],
) -> tuple[ProjectileImpact | None, ...]:
    previous_projectile_id = 0
    for impact in impacts:
        if not isinstance(impact, ProjectileImpact):
            raise ValueError("suppression resolution requires projectile impacts")
        if impact.tick != state.tick:
            raise ValueError("suppression impacts must match the state tick")
        if impact.projectile.projectile_id.value <= previous_projectile_id:
            raise ValueError("suppression impacts must be projectile-ID ordered")
        previous_projectile_id = impact.projectile.projectile_id.value
    impact_index = 0
    source_impacts: list[ProjectileImpact | None] = []
    for projectile in sources.entries:
        candidate_impact = impacts[impact_index] if impact_index < len(impacts) else None
        if (
            candidate_impact is not None
            and candidate_impact.projectile.projectile_id.value < projectile.projectile_id.value
        ):
            raise ValueError("suppression impacts must reference source projectiles")
        if (
            candidate_impact is not None
            and candidate_impact.projectile.projectile_id == projectile.projectile_id
        ):
            if candidate_impact.projectile != projectile:
                raise ValueError("suppression impact projectile must match its source projectile")
            source_impacts.append(candidate_impact)
            impact_index += 1
            continue
        source_impacts.append(None)
    if impact_index != len(impacts):
        raise ValueError("suppression impacts must reference source projectiles")
    return tuple(source_impacts)


def _direct_operative_target(impact: ProjectileImpact | None) -> EntityId | None:
    if impact is None or impact.collision.kind is not ProjectileCollisionKind.OPERATIVE:
        return None
    target_id = impact.collision.target_id
    if not isinstance(target_id, EntityId):
        raise AssertionError("operative impact target must be an entity ID")
    return target_id


def _is_within_point_radius(
    position: WorldPosition,
    point: WorldPosition,
    radius_mm: int,
) -> bool:
    if position.elevation != point.elevation:
        return False
    delta_x = position.x.value - point.x.value
    delta_y = position.y.value - point.y.value
    return delta_x * delta_x + delta_y * delta_y <= radius_mm * radius_mm


def _is_within_segment_radius(
    position: WorldPosition,
    start: WorldPosition,
    end: WorldPosition,
    radius_mm: int,
) -> bool:
    if position.elevation != start.elevation:
        return False
    delta_x = end.x.value - start.x.value
    delta_y = end.y.value - start.y.value
    offset_x = position.x.value - start.x.value
    offset_y = position.y.value - start.y.value
    segment_length_squared = delta_x * delta_x + delta_y * delta_y
    radius_squared = radius_mm * radius_mm
    if segment_length_squared == 0:
        return offset_x * offset_x + offset_y * offset_y <= radius_squared
    projection = offset_x * delta_x + offset_y * delta_y
    if projection <= 0:
        return offset_x * offset_x + offset_y * offset_y <= radius_squared
    if projection >= segment_length_squared:
        end_offset_x = position.x.value - end.x.value
        end_offset_y = position.y.value - end.y.value
        return end_offset_x * end_offset_x + end_offset_y * end_offset_y <= radius_squared
    cross_product = offset_x * delta_y - offset_y * delta_x
    return cross_product * cross_product <= radius_squared * segment_length_squared
