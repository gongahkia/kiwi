"""Deterministic selected-fire validation, ammunition use, and projectile spawning."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum
from math import isqrt

from kiwi.domain.geometry import WorldPosition, WorldSubunits, WorldVector
from kiwi.sim.arbitration import ArbitrationStatus, IntentionCandidate, PolicyArbitrationPhase
from kiwi.sim.intentions import FireIntention
from kiwi.sim.projectiles import Projectile, ProjectileStore
from kiwi.sim.state import EntityState, MissionState
from kiwi.sim.weapons import Ammunition, EquippedWeapon, WeaponStore

PROJECTILE_SPEED_MM_PER_TICK = 1_000
PROJECTILE_LIFETIME_TICKS = 30


class FireResolutionStatus(StrEnum):
    """The closed result of one selected fire request."""

    FIRED = "fired"
    REJECTED = "rejected"


class FireRejectionReason(StrEnum):
    """Stable fire failures after policy validation and arbitration."""

    INCAPACITATED = "incapacitated"
    WEAPON_NOT_FOUND = "weapon_not_found"
    WEAPON_NOT_OWNED = "weapon_not_owned"
    AMMUNITION_EMPTY = "ammunition_empty"
    TARGET_COINCIDENT = "target_coincident"


@dataclass(frozen=True, slots=True)
class FireResolution:
    """One source-linked fire result and, on success, its spawned projectile."""

    candidate: IntentionCandidate
    status: FireResolutionStatus
    projectile: Projectile | None = None
    reason: FireRejectionReason | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.candidate, IntentionCandidate):
            raise ValueError("fire resolution requires an intention candidate")
        if not isinstance(self.candidate.intention, FireIntention):
            raise ValueError("fire resolution requires a fire intention")
        if not isinstance(self.status, FireResolutionStatus):
            raise ValueError("fire resolution requires a status")
        if self.status is FireResolutionStatus.FIRED:
            if not isinstance(self.projectile, Projectile) or self.reason is not None:
                raise ValueError("fired resolutions require only a projectile")
            if self.projectile.owner_entity_id != self.candidate.origin.issuer_entity_id:
                raise ValueError("fired projectile owner must match fire issuer")
            if self.projectile.source_intention_id != self.candidate.origin.intention_id:
                raise ValueError("fired projectile must retain its source intention")
            return
        if self.projectile is not None or not isinstance(self.reason, FireRejectionReason):
            raise ValueError("rejected fire resolutions require only a rejection reason")


@dataclass(frozen=True, slots=True)
class FireExecutionPhase:
    """One successor state and intention-ID-ordered selected-fire results."""

    state: MissionState
    resolutions: tuple[FireResolution, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("fire execution requires mission state")
        if not isinstance(self.resolutions, tuple):
            raise ValueError("fire resolutions must be immutable")
        previous_intention_id = 0
        for resolution in self.resolutions:
            if not isinstance(resolution, FireResolution):
                raise ValueError("fire execution must contain fire resolutions")
            intention_id = resolution.candidate.origin.intention_id.value
            if intention_id <= previous_intention_id:
                raise ValueError("fire resolutions must be intention-ID ordered")
            previous_intention_id = intention_id
            if (
                resolution.status is FireResolutionStatus.FIRED
                and resolution.projectile not in self.state.projectiles.entries
            ):
                raise ValueError("fire execution state must retain fired projectiles")


def resolve_selected_fire(
    state: MissionState,
    arbitration: PolicyArbitrationPhase,
) -> FireExecutionPhase:
    """Resolve selected fire requests after movement and aim but before impacts."""
    if not isinstance(state, MissionState):
        raise TypeError("fire execution requires mission state")
    if not isinstance(arbitration, PolicyArbitrationPhase):
        raise TypeError("fire execution requires an arbitration phase")
    if state.tick != arbitration.state.tick:
        raise ValueError("fire execution phases must share a mission tick")
    next_state = state
    resolutions: list[FireResolution] = []
    for decision in arbitration.decisions:
        if decision.status is not ArbitrationStatus.SELECTED:
            continue
        candidate = decision.candidate
        if not isinstance(candidate.intention, FireIntention):
            continue
        resolutions.append(_resolve_fire(next_state, candidate))
        resolution = resolutions[-1]
        if resolution.status is FireResolutionStatus.FIRED:
            if resolution.projectile is None:
                raise AssertionError("fired resolution must retain a projectile")
            next_state = _apply_fired_projectile(next_state, resolution)
    return FireExecutionPhase(next_state, tuple(resolutions))


def _resolve_fire(state: MissionState, candidate: IntentionCandidate) -> FireResolution:
    entity = _entity_for_candidate(state, candidate)
    if state.conditions.is_incapacitated(entity.entity_id):
        return FireResolution(
            candidate, FireResolutionStatus.REJECTED, reason=FireRejectionReason.INCAPACITATED
        )
    intention = candidate.intention
    if not isinstance(intention, FireIntention):
        raise AssertionError("selected fire candidate changed intention type")
    weapon = state.weapons.weapon_for(intention.weapon_id)
    if weapon is None:
        return FireResolution(
            candidate,
            FireResolutionStatus.REJECTED,
            reason=FireRejectionReason.WEAPON_NOT_FOUND,
        )
    if weapon.owner_entity_id != entity.entity_id:
        return FireResolution(
            candidate,
            FireResolutionStatus.REJECTED,
            reason=FireRejectionReason.WEAPON_NOT_OWNED,
        )
    if weapon.ammunition.loaded_rounds == 0:
        return FireResolution(
            candidate,
            FireResolutionStatus.REJECTED,
            reason=FireRejectionReason.AMMUNITION_EMPTY,
        )
    target = WorldPosition(intention.target.x, intention.target.y, entity.position.elevation)
    if target == entity.position:
        return FireResolution(
            candidate,
            FireResolutionStatus.REJECTED,
            reason=FireRejectionReason.TARGET_COINCIDENT,
        )
    projectile_id, _ = state.id_allocator.allocate_projectile()
    return FireResolution(
        candidate,
        FireResolutionStatus.FIRED,
        Projectile(
            projectile_id,
            entity.entity_id,
            candidate.origin.intention_id,
            entity.position,
            _velocity_toward(entity.position, target),
            PROJECTILE_LIFETIME_TICKS,
        ),
    )


def _apply_fired_projectile(state: MissionState, resolution: FireResolution) -> MissionState:
    if resolution.projectile is None:
        raise ValueError("fired projectile application requires a projectile")
    intention = resolution.candidate.intention
    if not isinstance(intention, FireIntention):
        raise AssertionError("fired resolution changed intention type")
    projectile = resolution.projectile
    weapon = state.weapons.weapon_for(intention.weapon_id)
    if weapon is None:
        raise AssertionError("fired projectile source weapon must remain equipped")
    allocated_projectile_id, id_allocator = state.id_allocator.allocate_projectile()
    if allocated_projectile_id != projectile.projectile_id:
        raise AssertionError("fired projectile allocation must retain its resolved ID")
    reduced_weapon = EquippedWeapon(
        weapon.weapon_id,
        weapon.owner_entity_id,
        Ammunition(weapon.ammunition.capacity, weapon.ammunition.loaded_rounds - 1),
    )
    return replace(
        state,
        id_allocator=id_allocator,
        weapons=_replace_weapon(state.weapons, reduced_weapon),
        aim_states=state.aim_states.with_quality(projectile.owner_entity_id, 0),
        projectiles=ProjectileStore(state.projectiles.entries + (projectile,)),
    )


def _replace_weapon(store: WeaponStore, replacement: EquippedWeapon) -> WeaponStore:
    return WeaponStore(
        tuple(
            replacement if weapon.weapon_id == replacement.weapon_id else weapon
            for weapon in store.entries
        )
    )


def _entity_for_candidate(state: MissionState, candidate: IntentionCandidate) -> EntityState:
    for entity in state.entities:
        if entity.entity_id == candidate.origin.issuer_entity_id:
            return entity
    raise ValueError("selected fire intention issuer is not a mission entity")


def _velocity_toward(start: WorldPosition, target: WorldPosition) -> WorldVector:
    delta_x = target.x.value - start.x.value
    delta_y = target.y.value - start.y.value
    squared_distance = delta_x * delta_x + delta_y * delta_y
    if squared_distance == 0:
        raise ValueError("fire velocity requires distinct source and target positions")
    return WorldVector(
        WorldSubunits(_scaled_velocity_component(delta_x, squared_distance)),
        WorldSubunits(_scaled_velocity_component(delta_y, squared_distance)),
    )


def _scaled_velocity_component(delta: int, squared_distance: int) -> int:
    magnitude = abs(delta) * PROJECTILE_SPEED_MM_PER_TICK
    floor = isqrt(magnitude * magnitude // squared_distance)
    if 4 * magnitude * magnitude >= (2 * floor + 1) * (2 * floor + 1) * squared_distance:
        floor += 1
    return -floor if delta < 0 else floor
