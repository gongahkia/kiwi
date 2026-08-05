"""Canonical bounded operative health, protection, and injury state."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EntityId

MAX_OPERATIVE_HEALTH = 3
MAX_OPERATIVE_PROTECTION = 1


class InjurySeverity(StrEnum):
    """The closed injury severity derived from current health."""

    NONE = "none"
    MINOR = "minor"
    SEVERE = "severe"
    INCAPACITATED = "incapacitated"


@dataclass(frozen=True, slots=True)
class OperativeCondition:
    """One entity's bounded health, consumable protection, and stabilisation state."""

    entity_id: EntityId
    health: int = MAX_OPERATIVE_HEALTH
    protection: int = MAX_OPERATIVE_PROTECTION
    stabilized: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("operative condition requires an entity ID")
        if not isinstance(self.health, int) or isinstance(self.health, bool):
            raise ValueError("operative health must be an integer")
        if not 0 <= self.health <= MAX_OPERATIVE_HEALTH:
            raise ValueError("operative health is outside the configured range")
        if not isinstance(self.protection, int) or isinstance(self.protection, bool):
            raise ValueError("operative protection must be an integer")
        if not 0 <= self.protection <= MAX_OPERATIVE_PROTECTION:
            raise ValueError("operative protection is outside the configured range")
        if not isinstance(self.stabilized, bool):
            raise ValueError("operative stabilization state must be boolean")

    @property
    def injury_severity(self) -> InjurySeverity:
        """Return the canonical severity band for this exact health value."""
        if self.health == MAX_OPERATIVE_HEALTH:
            return InjurySeverity.NONE
        if self.health == MAX_OPERATIVE_HEALTH - 1:
            return InjurySeverity.MINOR
        if self.health == 1:
            return InjurySeverity.SEVERE
        return InjurySeverity.INCAPACITATED

    @property
    def incapacitated(self) -> bool:
        """Return whether this condition prevents non-medical action."""
        return self.health == 0

    @property
    def is_default(self) -> bool:
        """Return whether this value is omitted from sparse canonical state."""
        return (
            self.health == MAX_OPERATIVE_HEALTH
            and self.protection == MAX_OPERATIVE_PROTECTION
            and not self.stabilized
        )


@dataclass(frozen=True, slots=True)
class OperativeConditionStore:
    """An entity-ID-ordered sparse store whose absence is a healthy default."""

    entries: tuple[OperativeCondition, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.entries, tuple):
            raise ValueError("operative conditions must be an immutable tuple")
        previous_entity_id = 0
        for condition in self.entries:
            if not isinstance(condition, OperativeCondition):
                raise ValueError("operative conditions must contain operative conditions")
            if condition.entity_id.value <= previous_entity_id:
                raise ValueError("operative conditions must be entity-ID ordered")
            if condition.is_default:
                raise ValueError("operative conditions must omit default values")
            previous_entity_id = condition.entity_id.value

    def condition_for(self, entity_id: EntityId) -> OperativeCondition:
        """Return one condition without relying on unordered lookup."""
        if not isinstance(entity_id, EntityId):
            raise ValueError("operative condition lookup requires an entity ID")
        for condition in self.entries:
            if condition.entity_id == entity_id:
                return condition
        return OperativeCondition(entity_id)

    def is_incapacitated(self, entity_id: EntityId) -> bool:
        """Return whether one entity is incapable of non-medical action."""
        return self.condition_for(entity_id).incapacitated

    def with_condition(self, condition: OperativeCondition) -> OperativeConditionStore:
        """Insert, replace, or sparsely remove one entity condition."""
        if not isinstance(condition, OperativeCondition):
            raise ValueError("operative condition update requires an operative condition")
        entries = tuple(entry for entry in self.entries if entry.entity_id != condition.entity_id)
        if condition.is_default:
            return OperativeConditionStore(entries)
        return OperativeConditionStore(
            tuple(sorted(entries + (condition,), key=lambda entry: entry.entity_id.value))
        )
