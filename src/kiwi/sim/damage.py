"""Deterministic operative damage resolution from projectile impacts."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.domain.ids import EntityId
from kiwi.sim.conditions import InjurySeverity, OperativeCondition
from kiwi.sim.covers import CoverReservationStore
from kiwi.sim.projectile_impacts import ProjectileImpact
from kiwi.sim.projectile_sweeps import ProjectileCollisionKind
from kiwi.sim.state import MissionState

PROJECTILE_IMPACT_DAMAGE = 1


@dataclass(frozen=True, slots=True)
class DamageResolution:
    """One exact operative-impact damage calculation and condition successor."""

    impact: ProjectileImpact
    target_entity_id: EntityId
    health_before: int
    protection_before: int
    protection_absorbed: int
    health_damage: int
    health_after: int
    protection_after: int
    injury_before: InjurySeverity
    injury_after: InjurySeverity
    stabilized_before: bool
    stabilized_after: bool

    def __post_init__(self) -> None:
        if not isinstance(self.impact, ProjectileImpact):
            raise ValueError("damage resolution requires a projectile impact")
        if self.impact.collision.kind is not ProjectileCollisionKind.OPERATIVE:
            raise ValueError("damage resolution requires an operative impact")
        if not isinstance(self.impact.collision.target_id, EntityId):
            raise ValueError("operative impact target must be an entity ID")
        if self.target_entity_id != self.impact.collision.target_id:
            raise ValueError("damage target must match its operative impact")
        values = (
            self.health_before,
            self.protection_before,
            self.protection_absorbed,
            self.health_damage,
            self.health_after,
            self.protection_after,
        )
        if any(not isinstance(value, int) or isinstance(value, bool) for value in values):
            raise ValueError("damage resolution values must be integers")
        before = OperativeCondition(
            self.target_entity_id,
            self.health_before,
            self.protection_before,
            self.stabilized_before,
        )
        after = OperativeCondition(
            self.target_entity_id,
            self.health_after,
            self.protection_after,
            self.stabilized_after,
        )
        if not isinstance(self.injury_before, InjurySeverity):
            raise ValueError("damage resolution requires an injury severity before impact")
        if not isinstance(self.injury_after, InjurySeverity):
            raise ValueError("damage resolution requires an injury severity after impact")
        if not isinstance(self.stabilized_before, bool) or not isinstance(
            self.stabilized_after, bool
        ):
            raise ValueError("damage resolution stabilization values must be boolean")
        if self.injury_before is not before.injury_severity:
            raise ValueError("damage resolution prior injury must match prior health")
        if self.injury_after is not after.injury_severity:
            raise ValueError("damage resolution resulting injury must match resulting health")
        if self.protection_absorbed != min(PROJECTILE_IMPACT_DAMAGE, self.protection_before):
            raise ValueError("damage resolution protection absorption is invalid")
        penetrating_damage = PROJECTILE_IMPACT_DAMAGE - self.protection_absorbed
        if self.health_damage != min(self.health_before, penetrating_damage):
            raise ValueError("damage resolution health damage is invalid")
        if self.health_after != self.health_before - self.health_damage:
            raise ValueError("damage resolution health successor is invalid")
        if self.protection_after != self.protection_before - self.protection_absorbed:
            raise ValueError("damage resolution protection successor is invalid")
        expected_stabilized = before.stabilized if self.health_damage == 0 else False
        if self.stabilized_after is not expected_stabilized:
            raise ValueError("damage resolution stabilization successor is invalid")

    @property
    def became_incapacitated(self) -> bool:
        """Return whether this impact entered the incapacitated health band."""
        return (
            self.injury_before is not InjurySeverity.INCAPACITATED
            and self.injury_after is InjurySeverity.INCAPACITATED
        )


@dataclass(frozen=True, slots=True)
class DamagePhase:
    """One state successor and projectile-ID-ordered operative damage results."""

    state: MissionState
    resolutions: tuple[DamageResolution, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("damage phase requires mission state")
        if not isinstance(self.resolutions, tuple):
            raise ValueError("damage phase resolutions must be immutable")
        previous_projectile_id = 0
        entity_ids = tuple(entity.entity_id for entity in self.state.entities)
        for resolution in self.resolutions:
            if not isinstance(resolution, DamageResolution):
                raise ValueError("damage phase must contain damage resolutions")
            if resolution.impact.tick != self.state.tick:
                raise ValueError("damage resolutions must share the state tick")
            projectile_id = resolution.impact.projectile.projectile_id
            if projectile_id.value <= previous_projectile_id:
                raise ValueError("damage resolutions must be projectile-ID ordered")
            if resolution.target_entity_id not in entity_ids:
                raise ValueError("damage target must belong to the mission")
            previous_projectile_id = projectile_id.value


def resolve_projectile_damage(
    state: MissionState,
    impacts: tuple[ProjectileImpact, ...],
) -> DamagePhase:
    """Apply fixed one-point damage from operative impacts in projectile-ID order."""
    if not isinstance(state, MissionState):
        raise ValueError("damage resolution requires mission state")
    if not isinstance(impacts, tuple):
        raise ValueError("damage resolution requires immutable projectile impacts")
    conditions = state.conditions
    resolutions: list[DamageResolution] = []
    previous_projectile_id = 0
    entity_ids = tuple(entity.entity_id for entity in state.entities)
    for impact in impacts:
        if not isinstance(impact, ProjectileImpact):
            raise ValueError("damage resolution requires projectile impacts")
        projectile_id = impact.projectile.projectile_id
        if projectile_id.value <= previous_projectile_id:
            raise ValueError("damage resolution impacts must be projectile-ID ordered")
        if impact.tick != state.tick:
            raise ValueError("damage resolution impacts must match the state tick")
        previous_projectile_id = projectile_id.value
        if impact.collision.kind is not ProjectileCollisionKind.OPERATIVE:
            continue
        target_id = impact.collision.target_id
        if not isinstance(target_id, EntityId):
            raise AssertionError("operative impact target must be an entity ID")
        if target_id not in entity_ids:
            raise ValueError("damage resolution target must belong to the mission")
        before = conditions.condition_for(target_id)
        resolution = _resolve_operative_impact(impact, before)
        conditions = conditions.with_condition(
            OperativeCondition(
                target_id,
                resolution.health_after,
                resolution.protection_after,
                resolution.stabilized_after,
            )
        )
        resolutions.append(resolution)
    next_state = replace(
        state,
        conditions=conditions,
        movement_actions=tuple(
            action
            for action in state.movement_actions
            if not conditions.is_incapacitated(action.entity_id)
        ),
        cover_reservations=CoverReservationStore(
            tuple(
                reservation
                for reservation in state.cover_reservations.entries
                if not conditions.is_incapacitated(reservation.entity_id)
            )
        ),
    )
    return DamagePhase(next_state, tuple(resolutions))


def _resolve_operative_impact(
    impact: ProjectileImpact,
    before: OperativeCondition,
) -> DamageResolution:
    target_id = impact.collision.target_id
    if not isinstance(target_id, EntityId):
        raise AssertionError("operative impact target must be an entity ID")
    protection_absorbed = min(PROJECTILE_IMPACT_DAMAGE, before.protection)
    penetrating_damage = PROJECTILE_IMPACT_DAMAGE - protection_absorbed
    health_damage = min(before.health, penetrating_damage)
    health_after = before.health - health_damage
    protection_after = before.protection - protection_absorbed
    stabilized_after = before.stabilized if health_damage == 0 else False
    after = OperativeCondition(target_id, health_after, protection_after, stabilized_after)
    return DamageResolution(
        impact,
        target_id,
        before.health,
        before.protection,
        protection_absorbed,
        health_damage,
        health_after,
        protection_after,
        before.injury_severity,
        after.injury_severity,
        before.stabilized,
        stabilized_after,
    )
