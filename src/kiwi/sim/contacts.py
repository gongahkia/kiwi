"""Owner-local uncertain contact values before lifecycle resolution."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import ContactId, EntityId
from kiwi.sim.limits import MAX_AUTHORITY_TICK

MAX_CONFIDENCE_BASIS_POINTS = 10_000


@dataclass(frozen=True, slots=True)
class ContactConfidence:
    """One inclusive 0–10,000 basis-point estimate confidence."""

    basis_points: int

    def __post_init__(self) -> None:
        if not isinstance(self.basis_points, int) or isinstance(self.basis_points, bool):
            raise ValueError("contact confidence must be an integer")
        if not 0 <= self.basis_points <= MAX_CONFIDENCE_BASIS_POINTS:
            raise ValueError("contact confidence must be between zero and 10,000 basis points")


@dataclass(frozen=True, slots=True)
class ContactAge:
    """One non-negative exact elapsed contact age in simulation ticks."""

    ticks: int

    def __post_init__(self) -> None:
        if not isinstance(self.ticks, int) or isinstance(self.ticks, bool):
            raise ValueError("contact age must be an integer")
        if not 0 <= self.ticks <= MAX_AUTHORITY_TICK:
            raise ValueError("contact age must fit non-negative signed 64-bit range")


@dataclass(frozen=True, slots=True)
class ContactEstimate:
    """One owner-local estimate without a hidden target-entity identifier."""

    contact_id: ContactId
    owner_entity_id: EntityId
    estimated_position: WorldPosition
    uncertainty_radius: WorldSubunits
    confidence: ContactConfidence
    last_observed_tick: int

    def __post_init__(self) -> None:
        if not isinstance(self.contact_id, ContactId):
            raise ValueError("contact estimate requires a contact ID")
        if not isinstance(self.owner_entity_id, EntityId):
            raise ValueError("contact estimate requires an owner entity ID")
        if not isinstance(self.estimated_position, WorldPosition):
            raise ValueError("contact estimate requires an estimated position")
        if not isinstance(self.uncertainty_radius, WorldSubunits):
            raise ValueError("contact estimate uncertainty requires world subunits")
        if self.uncertainty_radius.value < 0:
            raise ValueError("contact estimate uncertainty must be non-negative")
        if not isinstance(self.confidence, ContactConfidence):
            raise ValueError("contact estimate requires contact confidence")
        if not isinstance(self.last_observed_tick, int) or isinstance(
            self.last_observed_tick, bool
        ):
            raise ValueError("contact estimate last observation tick must be an integer")
        if not 0 <= self.last_observed_tick <= MAX_AUTHORITY_TICK:
            raise ValueError(
                "contact estimate last observation tick must fit non-negative signed 64-bit range"
            )

    def age_at(self, current_tick: int) -> ContactAge:
        """Return exact elapsed age, rejecting a tick before the observation."""
        if not isinstance(current_tick, int) or isinstance(current_tick, bool):
            raise ValueError("contact age tick must be an integer")
        if not self.last_observed_tick <= current_tick <= MAX_AUTHORITY_TICK:
            raise ValueError("contact age tick must not precede the last observation")
        return ContactAge(current_tick - self.last_observed_tick)
