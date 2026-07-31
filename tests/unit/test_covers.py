from __future__ import annotations

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldSubunits
from kiwi.domain.ids import ContactId, CoverId, EntityId, EventId
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactEstimate,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
)
from kiwi.sim.covers import (
    FULL_EXPOSURE_BASIS_POINTS,
    HIGH_COVER_PROTECTION_BASIS_POINTS,
    MAX_COVER_INTEGRITY_BASIS_POINTS,
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
    estimate_cover_exposure,
)
from kiwi.sim.visibility import SensorRange, visible_covers


def test_cover_segment_has_canonical_sides_slots_height_and_integrity() -> None:
    segment = _segment()

    assert segment.cover_id == CoverId(1)
    assert segment.height is CoverHeight.HIGH
    assert segment.integrity == CoverIntegrity(8_500)
    assert tuple(slot.side for slot in segment.slots) == (CoverSide.LEFT, CoverSide.RIGHT)
    assert segment.slot_for(0) == segment.slots[0]
    assert segment.slot_for(2) is None


def test_cover_store_uses_cover_id_order_without_unordered_lookup() -> None:
    first = _segment(CoverId(1))
    second = _segment(CoverId(2))
    store = CoverStore((first, second))

    assert store.segment_for(CoverId(2)) == second
    assert store.segment_for(CoverId(3)) is None
    with pytest.raises(ValueError, match="unique ascending"):
        CoverStore((second, first))


def test_visible_covers_use_same_layer_exact_segment_range_and_cover_id_order() -> None:
    first = _segment(CoverId(1))
    second = CoverSegment(
        CoverId(2),
        WorldPosition(WorldSubunits(1_001), WorldSubunits(0)),
        WorldPosition(WorldSubunits(2_000), WorldSubunits(0)),
        CoverHeight.LOW,
        CoverIntegrity(10_000),
        (CoverSlot(0, WorldPosition(WorldSubunits(1_001), WorldSubunits(-350)), CoverSide.LEFT),),
    )
    other_layer = CoverSegment(
        CoverId(3),
        WorldPosition(WorldSubunits(0), WorldSubunits(0), ElevationLayer(1)),
        WorldPosition(WorldSubunits(1_000), WorldSubunits(0), ElevationLayer(1)),
        CoverHeight.LOW,
        CoverIntegrity(10_000),
        (
            CoverSlot(
                0,
                WorldPosition(WorldSubunits(0), WorldSubunits(-350), ElevationLayer(1)),
                CoverSide.LEFT,
            ),
        ),
    )

    visible = visible_covers(
        CoverStore((first, second, other_layer)),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
        SensorRange(WorldSubunits(1_000)),
    )

    assert tuple(cover.cover_id for cover in visible) == (CoverId(1),)


def test_cover_exposure_uses_contact_estimate_side_height_and_integrity() -> None:
    segment = _segment()
    right_contact = _contact(1, 500, -1_000)
    left_contact = _contact(2, 500, 1_000)
    collinear_contact = _contact(3, 500, 0)

    protected = estimate_cover_exposure(segment, 0, right_contact)
    exposed = estimate_cover_exposure(segment, 0, left_contact)
    collinear = estimate_cover_exposure(segment, 0, collinear_contact)

    assert protected.basis_points == FULL_EXPOSURE_BASIS_POINTS - (
        HIGH_COVER_PROTECTION_BASIS_POINTS * 8_500 // FULL_EXPOSURE_BASIS_POINTS
    )
    assert exposed.basis_points == collinear.basis_points == FULL_EXPOSURE_BASIS_POINTS


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: CoverIntegrity(-1), "between zero"),
        (
            lambda: CoverIntegrity(MAX_COVER_INTEGRITY_BASIS_POINTS + 1),
            "between zero",
        ),
        (
            lambda: CoverSlot(
                0,
                WorldPosition(WorldSubunits(0), WorldSubunits(0)),
                "left",  # type: ignore[arg-type]
            ),
            "cover side",
        ),
        (
            lambda: CoverSegment(
                CoverId(1),
                WorldPosition(WorldSubunits(1_000), WorldSubunits(0)),
                WorldPosition(WorldSubunits(0), WorldSubunits(0)),
                CoverHeight.LOW,
                CoverIntegrity(1),
                (
                    CoverSlot(
                        0, WorldPosition(WorldSubunits(0), WorldSubunits(-350)), CoverSide.LEFT
                    ),
                ),
            ),
            "canonically ordered",
        ),
        (
            lambda: CoverSegment(
                CoverId(1),
                WorldPosition(WorldSubunits(0), WorldSubunits(0)),
                WorldPosition(WorldSubunits(1_000), WorldSubunits(0)),
                CoverHeight.LOW,
                CoverIntegrity(1),
                (),
            ),
            "between one and 16",
        ),
        (
            lambda: CoverSegment(
                CoverId(1),
                WorldPosition(WorldSubunits(0), WorldSubunits(0)),
                WorldPosition(WorldSubunits(1_000), WorldSubunits(0)),
                CoverHeight.LOW,
                CoverIntegrity(1),
                (
                    CoverSlot(
                        1, WorldPosition(WorldSubunits(0), WorldSubunits(-350)), CoverSide.LEFT
                    ),
                ),
            ),
            "contiguous ascending",
        ),
        (
            lambda: CoverSegment(
                CoverId(1),
                WorldPosition(WorldSubunits(0), WorldSubunits(0)),
                WorldPosition(WorldSubunits(1_000), WorldSubunits(0)),
                CoverHeight.LOW,
                CoverIntegrity(1),
                (
                    CoverSlot(
                        0,
                        WorldPosition(WorldSubunits(0), WorldSubunits(-350), ElevationLayer(1)),
                        CoverSide.LEFT,
                    ),
                ),
            ),
            "elevation",
        ),
    ),
)
def test_cover_values_reject_noncanonical_inputs(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def _segment(cover_id: CoverId | None = None) -> CoverSegment:
    if cover_id is None:
        cover_id = CoverId(1)
    return CoverSegment(
        cover_id,
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
        WorldPosition(WorldSubunits(1_000), WorldSubunits(0)),
        CoverHeight.HIGH,
        CoverIntegrity(8_500),
        (
            CoverSlot(0, WorldPosition(WorldSubunits(0), WorldSubunits(-350)), CoverSide.LEFT),
            CoverSlot(1, WorldPosition(WorldSubunits(1_000), WorldSubunits(350)), CoverSide.RIGHT),
        ),
    )


def _contact(contact_id: int, x: int, y: int) -> ContactEstimate:
    return ContactEstimate(
        ContactId(contact_id),
        EntityId(1),
        WorldPosition(WorldSubunits(x), WorldSubunits(y)),
        WorldSubunits(100),
        ContactConfidence(7_500),
        0,
        ContactProvenance(
            tuple(ContactFieldProvenance(field, (EventId(1),)) for field in ContactField)
        ),
    )
