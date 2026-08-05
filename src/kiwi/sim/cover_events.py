"""Canonical event emission for resolved TakeCover reservations."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.domain.ids import EventId, IntentionId
from kiwi.sim.cover_intentions import TakeCoverExecutionPhase
from kiwi.sim.covers import CoverReservationStatus
from kiwi.sim.events import (
    CanonicalEvent,
    CoverReservationGranted,
    CoverReservationRejected,
    EventHeader,
    IntentionSelected,
    canonical_event_order,
)
from kiwi.sim.state import MissionState


@dataclass(frozen=True, slots=True)
class TakeCoverEventPhase:
    """The successor allocation state and source-linked cover reservation events."""

    state: MissionState
    events: tuple[CanonicalEvent, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("take-cover events require mission state")
        if not isinstance(self.events, tuple):
            raise ValueError("take-cover events must be an immutable tuple")
        if canonical_event_order(self.events) != self.events:
            raise ValueError("take-cover events must be canonically ordered")


def emit_take_cover_events(
    phase: TakeCoverExecutionPhase,
    policy_events: tuple[CanonicalEvent, ...],
) -> TakeCoverEventPhase:
    """Emit exactly one grant or rejection event per selected TakeCover request."""
    if not isinstance(phase, TakeCoverExecutionPhase):
        raise TypeError("take-cover event emission requires an execution phase")
    if not isinstance(policy_events, tuple):
        raise TypeError("take-cover event emission requires immutable policy events")
    next_state = phase.state
    events: list[CanonicalEvent] = []
    for resolution in phase.resolutions:
        selected_event_id = _selected_event_id(
            policy_events,
            resolution.candidate.origin.intention_id,
        )
        event_id, id_allocator = next_state.id_allocator.allocate_event()
        next_state = replace(next_state, id_allocator=id_allocator)
        header = EventHeader(event_id, next_state.tick, (selected_event_id,))
        if resolution.status is CoverReservationStatus.GRANTED:
            reservation = next_state.cover_reservations.reservation_for_entity(
                resolution.candidate.origin.issuer_entity_id
            )
            if reservation is None:
                raise AssertionError("granted take-cover request must create a reservation")
            events.append(CoverReservationGranted(header, resolution, reservation))
        else:
            events.append(CoverReservationRejected(header, resolution))
    return TakeCoverEventPhase(next_state, tuple(events))


def _selected_event_id(events: tuple[CanonicalEvent, ...], intention_id: IntentionId) -> EventId:
    for event in events:
        if (
            isinstance(event, IntentionSelected)
            and event.resolution.candidate.origin.intention_id == intention_id
        ):
            return event.header.event_id
    raise ValueError("take-cover execution requires a selected intention event")
