"""Owner-local uncertain contacts and deterministic lifecycle operations."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import ContactId, EntityId, IdAllocator
from kiwi.sim.limits import MAX_AUTHORITY_TICK

MAX_CONFIDENCE_BASIS_POINTS = 10_000
CONTACT_CONFIDENCE_DECAY_PER_TICK = 100
CONTACT_UNCERTAINTY_GROWTH_PER_TICK = WorldSubunits(100)


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


@dataclass(frozen=True, slots=True)
class ContactSighting:
    """One visibility-associated contact update at the current lifecycle tick."""

    owner_entity_id: EntityId
    estimated_position: WorldPosition
    uncertainty_radius: WorldSubunits
    confidence: ContactConfidence
    contact_id: ContactId | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.owner_entity_id, EntityId):
            raise ValueError("contact sighting requires an owner entity ID")
        if not isinstance(self.estimated_position, WorldPosition):
            raise ValueError("contact sighting requires an estimated position")
        if not isinstance(self.uncertainty_radius, WorldSubunits):
            raise ValueError("contact sighting uncertainty requires world subunits")
        if self.uncertainty_radius.value < 0:
            raise ValueError("contact sighting uncertainty must be non-negative")
        if not isinstance(self.confidence, ContactConfidence):
            raise ValueError("contact sighting requires contact confidence")
        if self.contact_id is not None and not isinstance(self.contact_id, ContactId):
            raise ValueError("contact sighting contact ID must be a contact ID or absent")


@dataclass(frozen=True, slots=True)
class ContactStore:
    """An immutable owner-and-contact-ID-ordered contact mapping at one tick."""

    estimates: tuple[ContactEstimate, ...] = ()
    lifecycle_tick: int = 0

    def __post_init__(self) -> None:
        if not isinstance(self.estimates, tuple):
            raise ValueError("contact estimates must be an immutable tuple")
        if not isinstance(self.lifecycle_tick, int) or isinstance(self.lifecycle_tick, bool):
            raise ValueError("contact lifecycle tick must be an integer")
        if not 0 <= self.lifecycle_tick <= MAX_AUTHORITY_TICK:
            raise ValueError("contact lifecycle tick must fit non-negative signed 64-bit range")
        previous_key = (0, 0)
        contact_ids: tuple[ContactId, ...] = ()
        for estimate in self.estimates:
            if not isinstance(estimate, ContactEstimate):
                raise ValueError("contact estimates must contain contact estimates")
            key = _contact_key(estimate)
            if key <= previous_key:
                raise ValueError("contact estimates must be owner-and-contact-ID ordered")
            if estimate.contact_id in contact_ids:
                raise ValueError("contact estimates must have globally unique contact IDs")
            if estimate.confidence.basis_points == 0:
                raise ValueError("contact estimates must have positive confidence")
            if estimate.last_observed_tick > self.lifecycle_tick:
                raise ValueError("contact lifecycle tick must not precede an observation")
            previous_key = key
            contact_ids += (estimate.contact_id,)

    def estimate_for(
        self, owner_entity_id: EntityId, contact_id: ContactId
    ) -> ContactEstimate | None:
        """Return one owner-local contact without relying on mapping iteration order."""
        if not isinstance(owner_entity_id, EntityId):
            raise ValueError("contact lookup requires an owner entity ID")
        if not isinstance(contact_id, ContactId):
            raise ValueError("contact lookup requires a contact ID")
        for estimate in self.estimates:
            if (estimate.owner_entity_id, estimate.contact_id) == (owner_entity_id, contact_id):
                return estimate
        return None


def advance_contacts(store: ContactStore, current_tick: int) -> ContactStore:
    """Decay all contacts through a later authoritative tick and drop exhausted ones."""
    if not isinstance(store, ContactStore):
        raise ValueError("contact lifecycle requires a contact store")
    if not isinstance(current_tick, int) or isinstance(current_tick, bool):
        raise ValueError("contact lifecycle tick must be an integer")
    if not store.lifecycle_tick <= current_tick <= MAX_AUTHORITY_TICK:
        raise ValueError("contact lifecycle tick must not precede the stored tick")
    elapsed_ticks = current_tick - store.lifecycle_tick
    if elapsed_ticks == 0:
        return store
    retained: list[ContactEstimate] = []
    for estimate in store.estimates:
        confidence = max(
            0, estimate.confidence.basis_points - elapsed_ticks * CONTACT_CONFIDENCE_DECAY_PER_TICK
        )
        if confidence == 0:
            continue
        uncertainty = WorldSubunits(
            estimate.uncertainty_radius.value
            + elapsed_ticks * CONTACT_UNCERTAINTY_GROWTH_PER_TICK.value
        )
        retained.append(
            replace(
                estimate,
                uncertainty_radius=uncertainty,
                confidence=ContactConfidence(confidence),
            )
        )
    return ContactStore(tuple(retained), current_tick)


def apply_contact_sightings(
    store: ContactStore,
    id_allocator: IdAllocator,
    observation_tick: int,
    sightings: tuple[ContactSighting, ...],
) -> tuple[ContactStore, IdAllocator]:
    """Create or replace owner-local contacts from one canonical observation pass."""
    if not isinstance(store, ContactStore):
        raise ValueError("contact sightings require a contact store")
    if not isinstance(id_allocator, IdAllocator):
        raise ValueError("contact sightings require an ID allocator")
    if not isinstance(observation_tick, int) or isinstance(observation_tick, bool):
        raise ValueError("contact observation tick must be an integer")
    if observation_tick != store.lifecycle_tick:
        raise ValueError("contact observation tick must equal the contact lifecycle tick")
    if not isinstance(sightings, tuple):
        raise ValueError("contact sightings must be an immutable tuple")
    if any(not isinstance(sighting, ContactSighting) for sighting in sightings):
        raise ValueError("contact sightings must contain contact sightings")

    estimates = list(store.estimates)
    updated_keys: tuple[tuple[EntityId, ContactId], ...] = ()
    next_allocator = id_allocator
    for sighting in sorted(sightings, key=_sighting_key):
        if sighting.contact_id is None:
            if sighting.confidence.basis_points == 0:
                continue
            contact_id, next_allocator = next_allocator.allocate_contact()
        else:
            contact_id = sighting.contact_id
            key = (sighting.owner_entity_id, contact_id)
            if key in updated_keys:
                raise ValueError("contact sightings must update each contact at most once")
            index = _contact_index(estimates, key)
            if index is None:
                raise ValueError("contact sighting update requires an existing owner-local contact")
            del estimates[index]
            updated_keys += (key,)
            if sighting.confidence.basis_points == 0:
                continue
        estimates.append(
            ContactEstimate(
                contact_id=contact_id,
                owner_entity_id=sighting.owner_entity_id,
                estimated_position=sighting.estimated_position,
                uncertainty_radius=sighting.uncertainty_radius,
                confidence=sighting.confidence,
                last_observed_tick=observation_tick,
            )
        )
    return (
        ContactStore(tuple(sorted(estimates, key=_contact_key)), observation_tick),
        next_allocator,
    )


def _contact_key(estimate: ContactEstimate) -> tuple[int, int]:
    return (estimate.owner_entity_id.value, estimate.contact_id.value)


def _sighting_key(sighting: ContactSighting) -> tuple[int, int, int, int, int, int, int]:
    contact_id = 0 if sighting.contact_id is None else sighting.contact_id.value
    return (
        sighting.owner_entity_id.value,
        contact_id,
        sighting.estimated_position.x.value,
        sighting.estimated_position.y.value,
        sighting.estimated_position.elevation.value,
        sighting.uncertainty_radius.value,
        sighting.confidence.basis_points,
    )


def _contact_index(
    estimates: list[ContactEstimate], key: tuple[EntityId, ContactId]
) -> int | None:
    for index, estimate in enumerate(estimates):
        if (estimate.owner_entity_id, estimate.contact_id) == key:
            return index
    return None
