from __future__ import annotations

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldSubunits
from kiwi.domain.ids import CoverId
from kiwi.sim.covers import (
    MAX_COVER_INTEGRITY_BASIS_POINTS,
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)


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


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: CoverIntegrity(-1), "between zero"),
        (
            lambda: CoverIntegrity(MAX_COVER_INTEGRITY_BASIS_POINTS + 1),
            "between zero",
        ),
        (
            lambda: CoverSlot(  # type: ignore[arg-type]
                0, WorldPosition(WorldSubunits(0), WorldSubunits(0)), "left"
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
