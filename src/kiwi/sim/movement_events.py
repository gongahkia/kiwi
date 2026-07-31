"""Canonical event emission for resolved movement actions."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.sim.events import (
    CanonicalEvent,
    EventHeader,
    MovementArrived,
    MovementBlocked,
    MovementProgressed,
    canonical_event_order,
)
from kiwi.sim.movement import MovementPhase, MovementResolutionKind
from kiwi.sim.state import MissionState


@dataclass(frozen=True, slots=True)
class MovementEventPhase:
    """The successor allocation state and canonical movement event tuple."""

    state: MissionState
    events: tuple[CanonicalEvent, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("movement event phase requires mission state")
        if not isinstance(self.events, tuple):
            raise ValueError("movement event phase events must be an immutable tuple")
        if canonical_event_order(self.events) != self.events:
            raise ValueError("movement event phase events must be canonically ordered")


def emit_movement_events(phase: MovementPhase) -> MovementEventPhase:
    """Emit one canonical event for each entity-ID-ordered movement resolution."""
    if not isinstance(phase, MovementPhase):
        raise TypeError("movement events require a movement phase")
    next_state = phase.state
    events: list[CanonicalEvent] = []
    for resolution in phase.resolutions:
        event_id, id_allocator = next_state.id_allocator.allocate_event()
        next_state = replace(next_state, id_allocator=id_allocator)
        header = EventHeader(event_id, resolution.tick)
        if resolution.kind is MovementResolutionKind.PROGRESSED:
            events.append(MovementProgressed(header, resolution))
        elif resolution.kind is MovementResolutionKind.BLOCKED:
            events.append(MovementBlocked(header, resolution))
        elif resolution.kind is MovementResolutionKind.ARRIVED:
            events.append(MovementArrived(header, resolution))
        else:
            raise AssertionError("movement resolution kind is unsupported")
    return MovementEventPhase(next_state, tuple(events))
