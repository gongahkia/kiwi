"""Resolve selected TakeCover intentions into canonical slot reservations."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.domain.ids import IntentionId
from kiwi.sim.arbitration import ArbitrationStatus, IntentionCandidate, PolicyArbitrationPhase
from kiwi.sim.covers import (
    CoverReservationRejectionReason,
    CoverReservationRequest,
    CoverReservationResolution,
    CoverReservationStatus,
    CoverReservationStore,
    CoverSlot,
    resolve_cover_reservations,
)
from kiwi.sim.intentions import TakeCoverIntention
from kiwi.sim.state import MissionState


class TakeCoverRejectionReason(StrEnum):
    """Stable execution failures after a TakeCover intention is selected."""

    COVER_NOT_FOUND = "cover_not_found"
    SIDE_UNAVAILABLE = "side_unavailable"
    ENTITY_ALREADY_REQUESTED = "entity_already_requested"
    SLOT_RESERVED = "slot_reserved"
    SLOT_CONTESTED = "slot_contested"


@dataclass(frozen=True, slots=True)
class TakeCoverResolution:
    """One source-linked reservation result for a selected TakeCover intention."""

    candidate: IntentionCandidate
    status: CoverReservationStatus
    slot_index: int | None = None
    reason: TakeCoverRejectionReason | None = None
    competing_intention_id: IntentionId | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.candidate, IntentionCandidate):
            raise ValueError("take-cover resolution requires an intention candidate")
        if not isinstance(self.candidate.intention, TakeCoverIntention):
            raise ValueError("take-cover resolution requires a take-cover intention")
        if not isinstance(self.status, CoverReservationStatus):
            raise ValueError("take-cover resolution requires a reservation status")
        if self.slot_index is not None and (
            not isinstance(self.slot_index, int)
            or isinstance(self.slot_index, bool)
            or self.slot_index < 0
        ):
            raise ValueError("take-cover resolution slot index must be non-negative or absent")
        if self.status is CoverReservationStatus.GRANTED:
            if (
                self.slot_index is None
                or self.reason is not None
                or self.competing_intention_id is not None
            ):
                raise ValueError("granted take-cover resolutions require only a slot index")
            return
        if not isinstance(self.reason, TakeCoverRejectionReason):
            raise ValueError("rejected take-cover resolutions require a rejection reason")
        if self.reason in (
            TakeCoverRejectionReason.SLOT_RESERVED,
            TakeCoverRejectionReason.SLOT_CONTESTED,
        ):
            if self.slot_index is None or not isinstance(self.competing_intention_id, IntentionId):
                raise ValueError(
                    "slot-rejected take-cover resolutions require a slot and competitor"
                )
        elif self.competing_intention_id is not None:
            raise ValueError("non-slot take-cover rejections cannot name a competitor")


@dataclass(frozen=True, slots=True)
class TakeCoverExecutionPhase:
    """The successor reservation state and canonical TakeCover results."""

    state: MissionState
    resolutions: tuple[TakeCoverResolution, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("take-cover execution requires mission state")
        if not isinstance(self.resolutions, tuple):
            raise ValueError("take-cover resolutions must be an immutable tuple")
        previous_intention_id = 0
        for resolution in self.resolutions:
            if not isinstance(resolution, TakeCoverResolution):
                raise ValueError("take-cover execution must contain resolutions")
            intention_id = resolution.candidate.origin.intention_id.value
            if intention_id <= previous_intention_id:
                raise ValueError("take-cover resolutions must be intention-ID ordered")
            previous_intention_id = intention_id


def resolve_selected_take_cover(
    state: MissionState,
    arbitration: PolicyArbitrationPhase,
) -> TakeCoverExecutionPhase:
    """Reserve the first eligible requested-side slot for each selected intention."""
    if not isinstance(state, MissionState):
        raise TypeError("take-cover execution requires mission state")
    if not isinstance(arbitration, PolicyArbitrationPhase):
        raise TypeError("take-cover execution requires an arbitration phase")
    if state.tick != arbitration.state.tick:
        raise ValueError("take-cover execution phases must share a mission tick")
    candidates = tuple(
        decision.candidate
        for decision in arbitration.decisions
        if decision.status is ArbitrationStatus.SELECTED
        and isinstance(decision.candidate.intention, TakeCoverIntention)
    )
    provisional = state.cover_reservations
    requests: list[CoverReservationRequest] = []
    unavailable: list[TakeCoverResolution] = []
    for candidate in candidates:
        intention = candidate.intention
        if not isinstance(intention, TakeCoverIntention):
            raise AssertionError("selected take-cover candidate changed intention type")
        segment = state.covers.segment_for(intention.cover_id)
        if segment is None:
            unavailable.append(
                TakeCoverResolution(
                    candidate,
                    CoverReservationStatus.REJECTED,
                    reason=TakeCoverRejectionReason.COVER_NOT_FOUND,
                )
            )
            continue
        slots = tuple(slot for slot in segment.slots if slot.side is intention.side)
        if not slots:
            unavailable.append(
                TakeCoverResolution(
                    candidate,
                    CoverReservationStatus.REJECTED,
                    reason=TakeCoverRejectionReason.SIDE_UNAVAILABLE,
                )
            )
            continue
        slot = _select_slot(candidate, slots, provisional)
        request = CoverReservationRequest(
            intention.cover_id,
            slot.slot_index,
            candidate.origin.issuer_entity_id,
            candidate.origin.intention_id,
        )
        requests.append(request)
        proposed = resolve_cover_reservations(state.covers, provisional, (request,))
        if proposed.resolutions[0].status is CoverReservationStatus.GRANTED:
            provisional = proposed.reservations
    reservation_phase = resolve_cover_reservations(
        state.covers,
        state.cover_reservations,
        tuple(requests),
    )
    next_state = replace(state, cover_reservations=reservation_phase.reservations)
    resolutions = tuple(
        sorted(
            tuple(unavailable)
            + tuple(
                _take_cover_resolution(
                    _candidate_for_request(candidates, resolution.request.intention_id),
                    resolution,
                )
                for resolution in reservation_phase.resolutions
            ),
            key=lambda resolution: resolution.candidate.origin.intention_id.value,
        )
    )
    return TakeCoverExecutionPhase(next_state, resolutions)


def _select_slot(
    candidate: IntentionCandidate,
    slots: tuple[CoverSlot, ...],
    reservations: CoverReservationStore,
) -> CoverSlot:
    intention = candidate.intention
    if not isinstance(intention, TakeCoverIntention):
        raise ValueError("cover slot selection requires a take-cover intention")
    existing = reservations.reservation_for_entity(candidate.origin.issuer_entity_id)
    if existing is not None:
        for slot in slots:
            if slot.slot_index == existing.slot_index and existing.cover_id == intention.cover_id:
                return slot
    for slot in slots:
        if reservations.reservation_for_slot(intention.cover_id, slot.slot_index) is None:
            return slot
    return slots[0]


def _candidate_for_request(
    candidates: tuple[IntentionCandidate, ...], intention_id: IntentionId
) -> IntentionCandidate:
    for candidate in candidates:
        if candidate.origin.intention_id == intention_id:
            return candidate
    raise AssertionError("cover reservation request has no selected take-cover candidate")


def _take_cover_resolution(
    candidate: IntentionCandidate,
    resolution: CoverReservationResolution,
) -> TakeCoverResolution:
    if resolution.status is CoverReservationStatus.GRANTED:
        return TakeCoverResolution(candidate, resolution.status, resolution.request.slot_index)
    if resolution.reason is CoverReservationRejectionReason.COVER_NOT_FOUND:
        reason = TakeCoverRejectionReason.COVER_NOT_FOUND
    elif resolution.reason is CoverReservationRejectionReason.SLOT_NOT_FOUND:
        raise AssertionError("selected take-cover slot must belong to its cover segment")
    elif resolution.reason is CoverReservationRejectionReason.ENTITY_ALREADY_REQUESTED:
        reason = TakeCoverRejectionReason.ENTITY_ALREADY_REQUESTED
    elif resolution.reason is CoverReservationRejectionReason.SLOT_RESERVED:
        reason = TakeCoverRejectionReason.SLOT_RESERVED
    elif resolution.reason is CoverReservationRejectionReason.SLOT_CONTESTED:
        reason = TakeCoverRejectionReason.SLOT_CONTESTED
    else:
        raise AssertionError("cover reservation rejection reason is unsupported")
    return TakeCoverResolution(
        candidate,
        resolution.status,
        resolution.request.slot_index,
        reason,
        resolution.competing_intention_id,
    )
