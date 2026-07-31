from __future__ import annotations

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldSubunits
from kiwi.domain.ids import ContactId, EntityId
from kiwi.sim.contacts import (
    MAX_CONFIDENCE_BASIS_POINTS,
    ContactAge,
    ContactConfidence,
    ContactEstimate,
)
from kiwi.sim.limits import MAX_AUTHORITY_TICK


def test_contact_estimate_is_owner_local_uncertain_and_ages_by_ticks() -> None:
    estimate = ContactEstimate(
        ContactId(3),
        EntityId(2),
        WorldPosition(WorldSubunits(1_500), WorldSubunits(-250), ElevationLayer(1)),
        WorldSubunits(600),
        ContactConfidence(7_500),
        12,
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
    )

    with pytest.raises(ValueError, match="must not precede"):
        estimate.age_at(3)
