from __future__ import annotations

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldSubunits
from kiwi.domain.ids import ContactId, EntityId, EventId, IdAllocator
from kiwi.sim.contacts import (
    CONTACT_CONFIDENCE_DECAY_PER_TICK,
    CONTACT_UNCERTAINTY_GROWTH_PER_TICK,
    MAX_CONFIDENCE_BASIS_POINTS,
    ContactAge,
    ContactConfidence,
    ContactEstimate,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactSighting,
    ContactStore,
    advance_contacts,
    apply_contact_sightings,
    nearest_contact_for,
)
from kiwi.sim.limits import MAX_AUTHORITY_TICK

_DEFAULT_SIGHTING_CONFIDENCE = ContactConfidence(7_500)
_DEFAULT_PROVENANCE = ContactProvenance(
    tuple(ContactFieldProvenance(field, (EventId(1),)) for field in ContactField)
)


def test_contact_estimate_is_owner_local_uncertain_and_ages_by_ticks() -> None:
    estimate = ContactEstimate(
        ContactId(3),
        EntityId(2),
        WorldPosition(WorldSubunits(1_500), WorldSubunits(-250), ElevationLayer(1)),
        WorldSubunits(600),
        ContactConfidence(7_500),
        12,
        _DEFAULT_PROVENANCE,
    )

    assert estimate.contact_id == ContactId(3)
    assert estimate.owner_entity_id == EntityId(2)
    assert estimate.estimated_position == WorldPosition(
        WorldSubunits(1_500), WorldSubunits(-250), ElevationLayer(1)
    )
    assert estimate.uncertainty_radius == WorldSubunits(600)
    assert estimate.confidence == ContactConfidence(7_500)
    assert estimate.age_at(12) == ContactAge(0)
    assert estimate.age_at(19) == ContactAge(7)


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: ContactConfidence(-1), "between zero"),
        (lambda: ContactConfidence(MAX_CONFIDENCE_BASIS_POINTS + 1), "between zero"),
        (lambda: ContactAge(-1), "non-negative"),
        (
            lambda: ContactEstimate(
                ContactId(1),
                EntityId(1),
                WorldPosition(WorldSubunits(0), WorldSubunits(0)),
                WorldSubunits(-1),
                ContactConfidence(1),
                0,
                _DEFAULT_PROVENANCE,
            ),
            "uncertainty",
        ),
        (
            lambda: ContactEstimate(
                ContactId(1),
                EntityId(1),
                WorldPosition(WorldSubunits(0), WorldSubunits(0)),
                WorldSubunits(0),
                ContactConfidence(1),
                MAX_AUTHORITY_TICK + 1,
                _DEFAULT_PROVENANCE,
            ),
            "last observation",
        ),
    ),
)
def test_contact_values_reject_invalid_ranges(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def test_contact_age_rejects_a_tick_before_the_last_observation() -> None:
    estimate = ContactEstimate(
        ContactId(1),
        EntityId(1),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
        WorldSubunits(0),
        ContactConfidence(10_000),
        4,
        _DEFAULT_PROVENANCE,
    )

    with pytest.raises(ValueError, match="must not precede"):
        estimate.age_at(3)


def test_nearest_contact_uses_exact_planar_distance_then_contact_id() -> None:
    owner = EntityId(1)
    store = ContactStore(
        (
            ContactEstimate(
                ContactId(1),
                owner,
                _position(3, 4),
                WorldSubunits(100),
                ContactConfidence(7_500),
                7,
                _DEFAULT_PROVENANCE,
            ),
            ContactEstimate(
                ContactId(2),
                owner,
                _position(-3, -4),
                WorldSubunits(100),
                ContactConfidence(7_500),
                7,
                _DEFAULT_PROVENANCE,
            ),
            ContactEstimate(
                ContactId(3),
                owner,
                _position(2, 0),
                WorldSubunits(100),
                ContactConfidence(7_500),
                7,
                _DEFAULT_PROVENANCE,
            ),
        ),
        lifecycle_tick=7,
    )

    assert nearest_contact_for(store, owner, _position(0, 0), 7) == store.estimates[2]
    tied_store = ContactStore(store.estimates[:2], lifecycle_tick=7)

    assert nearest_contact_for(tied_store, owner, _position(0, 0), 7) == tied_store.estimates[0]


def test_contact_provenance_resolves_each_policy_relevant_field_to_evidence_events() -> None:
    provenance = ContactProvenance(
        (
            ContactFieldProvenance(ContactField.ESTIMATED_POSITION, (EventId(1), EventId(3))),
            ContactFieldProvenance(ContactField.UNCERTAINTY_RADIUS, (EventId(1),)),
            ContactFieldProvenance(ContactField.CONFIDENCE, (EventId(1), EventId(2))),
            ContactFieldProvenance(ContactField.LAST_OBSERVED_TICK, (EventId(1),)),
        )
    )

    assert provenance.evidence_for(ContactField.ESTIMATED_POSITION) == (EventId(1), EventId(3))
    assert provenance.evidence_for(ContactField.UNCERTAINTY_RADIUS) == (EventId(1),)
    assert provenance.evidence_for(ContactField.CONFIDENCE) == (EventId(1), EventId(2))
    assert provenance.evidence_for(ContactField.LAST_OBSERVED_TICK) == (EventId(1),)


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: ContactFieldProvenance(ContactField.CONFIDENCE, ()),
            "between one and 64",
        ),
        (
            lambda: ContactFieldProvenance(ContactField.CONFIDENCE, (EventId(2), EventId(1))),
            "unique and ascending",
        ),
        (
            lambda: ContactProvenance(
                tuple(
                    ContactFieldProvenance(field, (EventId(1),))
                    for field in tuple(ContactField)[:-1]
                )
            ),
            "cover every",
        ),
    ),
)
def test_contact_provenance_rejects_incomplete_or_noncanonical_evidence(
    factory: object, message: str
) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def test_contact_sightings_allocate_canonically_and_replace_owner_local_estimates() -> None:
    owner_one = EntityId(1)
    owner_two = EntityId(2)
    first_store, allocator = apply_contact_sightings(
        ContactStore(lifecycle_tick=4),
        IdAllocator(),
        4,
        (
            _sighting(owner_two, 2_000, 5_000),
            _sighting(owner_one, 1_000, 4_000),
        ),
    )

    assert tuple(
        (estimate.owner_entity_id, estimate.contact_id) for estimate in first_store.estimates
    ) == ((owner_one, ContactId(1)), (owner_two, ContactId(2)))
    assert first_store.estimate_for(owner_one, ContactId(1)) == ContactEstimate(
        ContactId(1),
        owner_one,
        _position(1_000, 4_000),
        WorldSubunits(300),
        ContactConfidence(7_500),
        4,
        _DEFAULT_PROVENANCE,
    )

    second_store, updated_allocator = apply_contact_sightings(
        first_store,
        allocator,
        4,
        (
            _sighting(
                owner_one,
                1_500,
                4_500,
                provenance=_provenance(EventId(2)),
                contact_id=ContactId(1),
            ),
        ),
    )

    assert updated_allocator == allocator
    assert second_store.estimate_for(owner_one, ContactId(1)) == ContactEstimate(
        ContactId(1),
        owner_one,
        _position(1_500, 4_500),
        WorldSubunits(300),
        ContactConfidence(7_500),
        4,
        _provenance(EventId(2)),
    )
    assert second_store.estimate_for(owner_two, ContactId(2)) == first_store.estimate_for(
        owner_two, ContactId(2)
    )


def test_contact_lifecycle_decays_uncertainty_and_removes_exhausted_contacts() -> None:
    estimate = ContactEstimate(
        ContactId(1),
        EntityId(1),
        _position(10, 20),
        WorldSubunits(300),
        ContactConfidence(250),
        5,
        _DEFAULT_PROVENANCE,
    )
    store = ContactStore((estimate,), lifecycle_tick=5)

    first = advance_contacts(store, 6)
    second = advance_contacts(first, 7)
    lost = advance_contacts(second, 8)

    assert first.estimates[0].confidence == ContactConfidence(
        250 - CONTACT_CONFIDENCE_DECAY_PER_TICK
    )
    assert first.estimates[0].uncertainty_radius == WorldSubunits(
        300 + CONTACT_UNCERTAINTY_GROWTH_PER_TICK.value
    )
    assert second.estimates[0].confidence == ContactConfidence(50)
    assert second.estimates[0].last_observed_tick == 5
    assert second.estimates[0].provenance == _DEFAULT_PROVENANCE
    assert lost.estimates == ()
    assert lost.lifecycle_tick == 8


def test_zero_confidence_sightings_remove_contacts_without_allocating_a_replacement() -> None:
    owner = EntityId(1)
    store, allocator = apply_contact_sightings(
        ContactStore(lifecycle_tick=1), IdAllocator(), 1, (_sighting(owner, 100, 200),)
    )

    removed, after_removal = apply_contact_sightings(
        store,
        allocator,
        1,
        (_sighting(owner, 100, 200, confidence=ContactConfidence(0), contact_id=ContactId(1)),),
    )
    ignored, after_ignored = apply_contact_sightings(
        removed,
        after_removal,
        1,
        (_sighting(owner, 100, 200, confidence=ContactConfidence(0)),),
    )

    assert removed.estimates == ()
    assert after_removal == allocator
    assert ignored == removed
    assert after_ignored == after_removal


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: ContactStore(
                (
                    ContactEstimate(
                        ContactId(1),
                        EntityId(1),
                        _position(0, 0),
                        WorldSubunits(0),
                        ContactConfidence(100),
                        2,
                        _DEFAULT_PROVENANCE,
                    ),
                ),
                lifecycle_tick=1,
            ),
            "must not precede an observation",
        ),
        (
            lambda: advance_contacts(ContactStore(lifecycle_tick=3), 2),
            "must not precede the stored tick",
        ),
        (
            lambda: apply_contact_sightings(
                ContactStore(lifecycle_tick=1),
                IdAllocator(),
                1,
                (_sighting(EntityId(1), 0, 0, contact_id=ContactId(1)),),
            ),
            "requires an existing",
        ),
    ),
)
def test_contact_lifecycle_rejects_invalid_transition_inputs(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def _sighting(
    owner_entity_id: EntityId,
    x: int,
    y: int,
    *,
    confidence: ContactConfidence = _DEFAULT_SIGHTING_CONFIDENCE,
    provenance: ContactProvenance = _DEFAULT_PROVENANCE,
    contact_id: ContactId | None = None,
) -> ContactSighting:
    return ContactSighting(
        owner_entity_id,
        _position(x, y),
        WorldSubunits(300),
        confidence,
        provenance,
        contact_id,
    )


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y), ElevationLayer(1))


def _provenance(event_id: EventId) -> ContactProvenance:
    return ContactProvenance(
        tuple(ContactFieldProvenance(field, (event_id,)) for field in ContactField)
    )
