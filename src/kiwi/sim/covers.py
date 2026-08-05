"""Canonical cover geometry and slots for authoritative tactical state."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.geometry import WorldPosition
from kiwi.domain.ids import CoverId, EntityId, IntentionId
from kiwi.sim.contacts import ContactEstimate
from kiwi.sim.limits import MAX_AUTHORITY_TICK

MAX_COVER_INTEGRITY_BASIS_POINTS = 10_000
MAX_COVER_SLOTS_PER_SEGMENT = 16
FULL_EXPOSURE_BASIS_POINTS = 10_000
LOW_COVER_PROTECTION_BASIS_POINTS = 5_000
HIGH_COVER_PROTECTION_BASIS_POINTS = 7_500


class CoverSide(StrEnum):
    """One side of a canonically directed cover segment."""

    LEFT = "left"
    RIGHT = "right"


class CoverHeight(StrEnum):
    """The initial discrete protection-height classes."""

    LOW = "low"
    HIGH = "high"


class CoverReservationStatus(StrEnum):
    """One authoritative outcome while assigning a requested cover slot."""

    GRANTED = "granted"
    REJECTED = "rejected"


class CoverReservationRejectionReason(StrEnum):
    """Stable reasons a cover-slot claim cannot become a reservation."""

    COVER_NOT_FOUND = "cover_not_found"
    SLOT_NOT_FOUND = "slot_not_found"
    ENTITY_ALREADY_REQUESTED = "entity_already_requested"
    SLOT_RESERVED = "slot_reserved"
    SLOT_CONTESTED = "slot_contested"


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


@dataclass(frozen=True, slots=True)
class CoverReservation:
    """One persistent claim by an entity on one valid cover slot."""

    cover_id: CoverId
    slot_index: int
    entity_id: EntityId
    intention_id: IntentionId

    def __post_init__(self) -> None:
        if not isinstance(self.cover_id, CoverId):
            raise ValueError("cover reservation requires a cover ID")
        if not isinstance(self.slot_index, int) or isinstance(self.slot_index, bool):
            raise ValueError("cover reservation slot index must be an integer")
        if self.slot_index < 0:
            raise ValueError("cover reservation slot index must be non-negative")
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("cover reservation requires an entity ID")
        if not isinstance(self.intention_id, IntentionId):
            raise ValueError("cover reservation requires an intention ID")


@dataclass(frozen=True, slots=True)
class CoverReservationStore:
    """A canonical cover-slot-ordered sparse reservation store."""

    entries: tuple[CoverReservation, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.entries, tuple):
            raise ValueError("cover reservations must be an immutable tuple")
        previous_key = (0, -1)
        entity_ids: tuple[EntityId, ...] = ()
        for reservation in self.entries:
            if not isinstance(reservation, CoverReservation):
                raise ValueError("cover reservations must contain cover reservations")
            key = (reservation.cover_id.value, reservation.slot_index)
            if key <= previous_key:
                raise ValueError("cover reservations must have unique ascending cover slots")
            if reservation.entity_id in entity_ids:
                raise ValueError("cover reservations must have unique entity IDs")
            previous_key = key
            entity_ids += (reservation.entity_id,)

    def reservation_for_slot(self, cover_id: CoverId, slot_index: int) -> CoverReservation | None:
        """Return one slot claim without using an unordered lookup."""
        if not isinstance(cover_id, CoverId):
            raise ValueError("cover reservation lookup requires a cover ID")
        if not isinstance(slot_index, int) or isinstance(slot_index, bool):
            raise ValueError("cover reservation lookup requires an integer slot index")
        for reservation in self.entries:
            if reservation.cover_id == cover_id and reservation.slot_index == slot_index:
                return reservation
        return None

    def reservation_for_entity(self, entity_id: EntityId) -> CoverReservation | None:
        """Return one entity claim without using an unordered lookup."""
        if not isinstance(entity_id, EntityId):
            raise ValueError("cover reservation lookup requires an entity ID")
        for reservation in self.entries:
            if reservation.entity_id == entity_id:
                return reservation
        return None


@dataclass(frozen=True, slots=True)
class CoverReservationRequest:
    """One selected intent's request for an exclusive cover slot."""

    cover_id: CoverId
    slot_index: int
    entity_id: EntityId
    intention_id: IntentionId
    priority: int = 0

    def __post_init__(self) -> None:
        if not isinstance(self.cover_id, CoverId):
            raise ValueError("cover reservation request requires a cover ID")
        if not isinstance(self.slot_index, int) or isinstance(self.slot_index, bool):
            raise ValueError("cover reservation request slot index must be an integer")
        if self.slot_index < 0:
            raise ValueError("cover reservation request slot index must be non-negative")
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("cover reservation request requires an entity ID")
        if not isinstance(self.intention_id, IntentionId):
            raise ValueError("cover reservation request requires an intention ID")
        if not isinstance(self.priority, int) or isinstance(self.priority, bool):
            raise ValueError("cover reservation request priority must be an integer")
        if not 0 <= self.priority <= MAX_AUTHORITY_TICK:
            raise ValueError(
                "cover reservation request priority must fit non-negative signed 64-bit range"
            )


@dataclass(frozen=True, slots=True)
class CoverReservationResolution:
    """One deterministic result for a requested cover slot."""

    request: CoverReservationRequest
    status: CoverReservationStatus
    reason: CoverReservationRejectionReason | None = None
    competing_intention_id: IntentionId | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.request, CoverReservationRequest):
            raise ValueError("cover reservation resolution requires a request")
        if not isinstance(self.status, CoverReservationStatus):
            raise ValueError("cover reservation resolution requires a status")
        if self.status is CoverReservationStatus.GRANTED:
            if self.reason is not None or self.competing_intention_id is not None:
                raise ValueError("granted cover reservations cannot have a rejection reason")
            return
        if not isinstance(self.reason, CoverReservationRejectionReason):
            raise ValueError("rejected cover reservations require a rejection reason")
        if self.reason in (
            CoverReservationRejectionReason.SLOT_RESERVED,
            CoverReservationRejectionReason.SLOT_CONTESTED,
        ):
            if not isinstance(self.competing_intention_id, IntentionId):
                raise ValueError(
                    "slot-rejected cover reservations require a competing intention ID"
                )
        elif self.competing_intention_id is not None:
            raise ValueError("non-slot cover reservation rejections cannot name a competitor")


@dataclass(frozen=True, slots=True)
class CoverReservationPhase:
    """The successor reservation store and canonical request outcomes."""

    reservations: CoverReservationStore
    resolutions: tuple[CoverReservationResolution, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.reservations, CoverReservationStore):
            raise ValueError("cover reservation phase requires a reservation store")
        if not isinstance(self.resolutions, tuple):
            raise ValueError("cover reservation phase resolutions must be an immutable tuple")
        previous_key = (-1, 0, 0)
        for resolution in self.resolutions:
            if not isinstance(resolution, CoverReservationResolution):
                raise ValueError("cover reservation phase must contain resolutions")
            request = resolution.request
            key = (request.priority, request.entity_id.value, request.intention_id.value)
            if key <= previous_key:
                raise ValueError(
                    "cover reservation phase resolutions must use canonical request order"
                )
            previous_key = key


def resolve_cover_reservations(
    covers: CoverStore,
    reservations: CoverReservationStore,
    requests: tuple[CoverReservationRequest, ...],
) -> CoverReservationPhase:
    """Resolve slot claims by priority, entity ID, then intention ID."""
    if not isinstance(covers, CoverStore):
        raise TypeError("cover reservation resolution requires a cover store")
    if not isinstance(reservations, CoverReservationStore):
        raise TypeError("cover reservation resolution requires a reservation store")
    if not isinstance(requests, tuple):
        raise TypeError("cover reservation requests must be an immutable tuple")
    if any(not isinstance(request, CoverReservationRequest) for request in requests):
        raise ValueError("cover reservation requests must contain reservation requests")
    intention_ids: tuple[IntentionId, ...] = ()
    for request in requests:
        if request.intention_id in intention_ids:
            raise ValueError("cover reservation requests must have unique intention IDs")
        intention_ids += (request.intention_id,)
    ordered_requests = tuple(sorted(requests, key=_reservation_request_key))
    current = list(reservations.entries)
    resolutions: list[CoverReservationResolution] = []
    requested_entities: tuple[EntityId, ...] = ()
    newly_granted_intention_ids: tuple[IntentionId, ...] = ()
    for request in ordered_requests:
        if request.entity_id in requested_entities:
            resolutions.append(
                CoverReservationResolution(
                    request,
                    CoverReservationStatus.REJECTED,
                    CoverReservationRejectionReason.ENTITY_ALREADY_REQUESTED,
                )
            )
            continue
        requested_entities += (request.entity_id,)
        segment = covers.segment_for(request.cover_id)
        if segment is None:
            resolutions.append(
                CoverReservationResolution(
                    request,
                    CoverReservationStatus.REJECTED,
                    CoverReservationRejectionReason.COVER_NOT_FOUND,
                )
            )
            continue
        if segment.slot_for(request.slot_index) is None:
            resolutions.append(
                CoverReservationResolution(
                    request,
                    CoverReservationStatus.REJECTED,
                    CoverReservationRejectionReason.SLOT_NOT_FOUND,
                )
            )
            continue
        existing = _reservation_for_entity(current, request.entity_id)
        target = _reservation_for_slot(current, request.cover_id, request.slot_index)
        if target is not None and target != existing:
            reason = (
                CoverReservationRejectionReason.SLOT_CONTESTED
                if target.intention_id in newly_granted_intention_ids
                else CoverReservationRejectionReason.SLOT_RESERVED
            )
            resolutions.append(
                CoverReservationResolution(
                    request,
                    CoverReservationStatus.REJECTED,
                    reason,
                    target.intention_id,
                )
            )
            continue
        if existing is not None:
            current.remove(existing)
        current.append(
            CoverReservation(
                request.cover_id,
                request.slot_index,
                request.entity_id,
                request.intention_id,
            )
        )
        newly_granted_intention_ids += (request.intention_id,)
        resolutions.append(CoverReservationResolution(request, CoverReservationStatus.GRANTED))
    ordered_reservations = tuple(sorted(current, key=_reservation_key))
    return CoverReservationPhase(CoverReservationStore(ordered_reservations), tuple(resolutions))


def _reservation_key(reservation: CoverReservation) -> tuple[int, int]:
    return (reservation.cover_id.value, reservation.slot_index)


def _reservation_request_key(request: CoverReservationRequest) -> tuple[int, int, int]:
    return (request.priority, request.entity_id.value, request.intention_id.value)


def _reservation_for_entity(
    reservations: list[CoverReservation], entity_id: EntityId
) -> CoverReservation | None:
    for reservation in reservations:
        if reservation.entity_id == entity_id:
            return reservation
    return None


def _reservation_for_slot(
    reservations: list[CoverReservation], cover_id: CoverId, slot_index: int
) -> CoverReservation | None:
    for reservation in reservations:
        if reservation.cover_id == cover_id and reservation.slot_index == slot_index:
            return reservation
    return None


@dataclass(frozen=True, slots=True)
class ExposureEstimate:
    """One deterministic slot exposure estimate against one contact estimate."""

    cover_id: CoverId
    slot_index: int
    contact_id: int
    basis_points: int

    def __post_init__(self) -> None:
        if not isinstance(self.cover_id, CoverId):
            raise ValueError("exposure estimate requires a cover ID")
        if not isinstance(self.slot_index, int) or isinstance(self.slot_index, bool):
            raise ValueError("exposure estimate slot index must be an integer")
        if not isinstance(self.contact_id, int) or isinstance(self.contact_id, bool):
            raise ValueError("exposure estimate contact ID must be an integer")
        if not 0 <= self.basis_points <= FULL_EXPOSURE_BASIS_POINTS:
            raise ValueError("exposure estimate must be between zero and 10,000 basis points")


def estimate_cover_exposure(
    segment: CoverSegment, slot_index: int, contact: ContactEstimate
) -> ExposureEstimate:
    """Estimate exposure from one uncertain contact without reading hidden target state."""
    if not isinstance(segment, CoverSegment):
        raise ValueError("cover exposure requires a cover segment")
    if not isinstance(contact, ContactEstimate):
        raise ValueError("cover exposure requires a contact estimate")
    slot = segment.slot_for(slot_index)
    if slot is None:
        raise ValueError("cover exposure slot index must exist on its segment")
    if contact.estimated_position.elevation != segment.start.elevation:
        return ExposureEstimate(
            segment.cover_id, slot_index, contact.contact_id.value, FULL_EXPOSURE_BASIS_POINTS
        )
    contact_side = _side_of_segment(segment, contact.estimated_position)
    if contact_side is None or contact_side is slot.side:
        return ExposureEstimate(
            segment.cover_id, slot_index, contact.contact_id.value, FULL_EXPOSURE_BASIS_POINTS
        )
    protection = (
        LOW_COVER_PROTECTION_BASIS_POINTS
        if segment.height is CoverHeight.LOW
        else HIGH_COVER_PROTECTION_BASIS_POINTS
    )
    protected = protection * segment.integrity.basis_points // FULL_EXPOSURE_BASIS_POINTS
    return ExposureEstimate(
        segment.cover_id,
        slot_index,
        contact.contact_id.value,
        FULL_EXPOSURE_BASIS_POINTS - protected,
    )


def _position_key(position: WorldPosition) -> tuple[int, int]:
    return (position.x.value, position.y.value)


def _side_of_segment(segment: CoverSegment, position: WorldPosition) -> CoverSide | None:
    vector_x = segment.end.x.value - segment.start.x.value
    vector_y = segment.end.y.value - segment.start.y.value
    offset_x = position.x.value - segment.start.x.value
    offset_y = position.y.value - segment.start.y.value
    cross = vector_x * offset_y - vector_y * offset_x
    if cross > 0:
        return CoverSide.LEFT
    if cross < 0:
        return CoverSide.RIGHT
    return None
