"""Canonical cover geometry and slots for authoritative tactical state."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.geometry import WorldPosition
from kiwi.domain.ids import CoverId

MAX_COVER_INTEGRITY_BASIS_POINTS = 10_000
MAX_COVER_SLOTS_PER_SEGMENT = 16


class CoverSide(StrEnum):
    """One side of a canonically directed cover segment."""

    LEFT = "left"
    RIGHT = "right"


class CoverHeight(StrEnum):
    """The initial discrete protection-height classes."""

    LOW = "low"
    HIGH = "high"


@dataclass(frozen=True, slots=True)
class CoverIntegrity:
    """One inclusive 0–10,000 basis-point structural-integrity value."""

    basis_points: int

    def __post_init__(self) -> None:
        if not isinstance(self.basis_points, int) or isinstance(self.basis_points, bool):
            raise ValueError("cover integrity must be an integer")
        if not 0 <= self.basis_points <= MAX_COVER_INTEGRITY_BASIS_POINTS:
            raise ValueError("cover integrity must be between zero and 10,000 basis points")


@dataclass(frozen=True, slots=True)
class CoverSlot:
    """One stable standing position on a specified side of a cover segment."""

    slot_index: int
    position: WorldPosition
    side: CoverSide

    def __post_init__(self) -> None:
        if not isinstance(self.slot_index, int) or isinstance(self.slot_index, bool):
            raise ValueError("cover slot index must be an integer")
        if not isinstance(self.position, WorldPosition):
            raise ValueError("cover slot requires a world position")
        if not isinstance(self.side, CoverSide):
            raise ValueError("cover slot requires a cover side")


@dataclass(frozen=True, slots=True)
class CoverSegment:
    """One directed, slotted, mutable-integrity cover edge."""

    cover_id: CoverId
    start: WorldPosition
    end: WorldPosition
    height: CoverHeight
    integrity: CoverIntegrity
    slots: tuple[CoverSlot, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.cover_id, CoverId):
            raise ValueError("cover segment requires a cover ID")
        if not isinstance(self.start, WorldPosition) or not isinstance(self.end, WorldPosition):
            raise ValueError("cover segment endpoints must be world positions")
        if self.start.elevation != self.end.elevation:
            raise ValueError("cover segment endpoints must share an elevation")
        if _position_key(self.start) >= _position_key(self.end):
            raise ValueError("cover segment endpoints must be distinct and canonically ordered")
        if not isinstance(self.height, CoverHeight):
            raise ValueError("cover segment requires a cover height")
        if not isinstance(self.integrity, CoverIntegrity):
            raise ValueError("cover segment requires cover integrity")
        if not isinstance(self.slots, tuple):
            raise ValueError("cover segment slots must be an immutable tuple")
        if not 1 <= len(self.slots) <= MAX_COVER_SLOTS_PER_SEGMENT:
            raise ValueError("cover segment must contain between one and 16 slots")
        slot_positions: tuple[WorldPosition, ...] = ()
        for expected_index, slot in enumerate(self.slots):
            if not isinstance(slot, CoverSlot):
                raise ValueError("cover segment slots must contain cover slots")
            if slot.slot_index != expected_index:
                raise ValueError("cover segment slots must use contiguous ascending indices")
            if slot.position.elevation != self.start.elevation:
                raise ValueError("cover slot elevation must match its cover segment")
            if slot.position in slot_positions:
                raise ValueError("cover segment slots must have unique positions")
            slot_positions += (slot.position,)

    def slot_for(self, slot_index: int) -> CoverSlot | None:
        """Return one local slot without relying on unordered lookup."""
        if not isinstance(slot_index, int) or isinstance(slot_index, bool):
            raise ValueError("cover slot lookup requires an integer index")
        if not 0 <= slot_index < len(self.slots):
            return None
        return self.slots[slot_index]


@dataclass(frozen=True, slots=True)
class CoverStore:
    """An immutable cover-ID-ordered collection for one mission."""

    segments: tuple[CoverSegment, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.segments, tuple):
            raise ValueError("cover store segments must be an immutable tuple")
        previous_id = 0
        for segment in self.segments:
            if not isinstance(segment, CoverSegment):
                raise ValueError("cover store segments must contain cover segments")
            if segment.cover_id.value <= previous_id:
                raise ValueError("cover store segments must have unique ascending cover IDs")
            previous_id = segment.cover_id.value

    def segment_for(self, cover_id: CoverId) -> CoverSegment | None:
        """Return one cover segment without relying on unordered lookup."""
        if not isinstance(cover_id, CoverId):
            raise ValueError("cover lookup requires a cover ID")
        for segment in self.segments:
            if segment.cover_id == cover_id:
                return segment
        return None


def _position_key(position: WorldPosition) -> tuple[int, int]:
    return (position.x.value, position.y.value)
