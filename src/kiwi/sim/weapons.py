"""Canonical equipped-weapon and target-free aim authority values."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.ids import EntityId, WeaponId

MAX_MAGAZINE_ROUNDS = 65_535
MAX_AIM_QUALITY_BASIS_POINTS = 10_000


@dataclass(frozen=True, slots=True)
class Ammunition:
    """One bounded magazine with explicit loaded rounds."""

    capacity: int
    loaded_rounds: int

    def __post_init__(self) -> None:
        if not isinstance(self.capacity, int) or isinstance(self.capacity, bool):
            raise ValueError("ammunition capacity must be an integer")
        if not 1 <= self.capacity <= MAX_MAGAZINE_ROUNDS:
            raise ValueError("ammunition capacity is outside the configured range")
        if not isinstance(self.loaded_rounds, int) or isinstance(self.loaded_rounds, bool):
            raise ValueError("loaded rounds must be an integer")
        if not 0 <= self.loaded_rounds <= self.capacity:
            raise ValueError("loaded rounds must be between zero and capacity")


@dataclass(frozen=True, slots=True)
class EquippedWeapon:
    """One generic weapon assigned to exactly one mission entity."""

    weapon_id: WeaponId
    owner_entity_id: EntityId
    ammunition: Ammunition

    def __post_init__(self) -> None:
        if not isinstance(self.weapon_id, WeaponId):
            raise ValueError("equipped weapon requires a weapon ID")
        if not isinstance(self.owner_entity_id, EntityId):
            raise ValueError("equipped weapon requires an owner entity ID")
        if not isinstance(self.ammunition, Ammunition):
            raise ValueError("equipped weapon requires ammunition")


@dataclass(frozen=True, slots=True)
class WeaponStore:
    """A weapon-ID-ordered immutable inventory for the mission."""

    entries: tuple[EquippedWeapon, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.entries, tuple):
            raise ValueError("weapon store entries must be an immutable tuple")
        previous_weapon_id = 0
        for entry in self.entries:
            if not isinstance(entry, EquippedWeapon):
                raise ValueError("weapon store entries must be equipped weapons")
            if entry.weapon_id.value <= previous_weapon_id:
                raise ValueError("weapon store entries must be weapon-ID ordered")
            previous_weapon_id = entry.weapon_id.value

    def weapon_for(self, weapon_id: WeaponId) -> EquippedWeapon | None:
        """Return one weapon without relying on unordered lookup."""
        if not isinstance(weapon_id, WeaponId):
            raise ValueError("weapon lookup requires a weapon ID")
        for entry in self.entries:
            if entry.weapon_id == weapon_id:
                return entry
        return None


@dataclass(frozen=True, slots=True)
class AimState:
    """One nonzero target-free aim quality retained for an operative."""

    entity_id: EntityId
    quality_basis_points: int

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("aim state requires an entity ID")
        if (
            not isinstance(self.quality_basis_points, int)
            or isinstance(self.quality_basis_points, bool)
            or not 1 <= self.quality_basis_points <= MAX_AIM_QUALITY_BASIS_POINTS
        ):
            raise ValueError("aim quality must be between one and 10,000")


@dataclass(frozen=True, slots=True)
class AimStore:
    """A sparse entity-ID-ordered aim-quality store; absent means zero quality."""

    entries: tuple[AimState, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.entries, tuple):
            raise ValueError("aim store entries must be an immutable tuple")
        previous_entity_id = 0
        for entry in self.entries:
            if not isinstance(entry, AimState):
                raise ValueError("aim store entries must be aim states")
            if entry.entity_id.value <= previous_entity_id:
                raise ValueError("aim store entries must be entity-ID ordered")
            previous_entity_id = entry.entity_id.value

    def quality_for(self, entity_id: EntityId) -> int:
        """Return retained quality or the canonical implicit zero."""
        if not isinstance(entity_id, EntityId):
            raise ValueError("aim lookup requires an entity ID")
        for entry in self.entries:
            if entry.entity_id == entity_id:
                return entry.quality_basis_points
        return 0
