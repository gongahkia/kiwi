"""Deterministic communication event emission over immutable message state."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.sim.events import (
    EventHeader,
    MessageDelivered,
    MessageSent,
    canonical_event_order,
)
from kiwi.sim.messages import Message
from kiwi.sim.state import MissionState


@dataclass(frozen=True, slots=True)
class MessageDeliveryPhase:
    """Successor allocation state and delivery events for one authority tick."""

    state: MissionState
    events: tuple[MessageDelivered, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("message delivery phase requires mission state")
        if not isinstance(self.events, tuple):
            raise ValueError("message delivery phase events must be an immutable tuple")
        if any(not isinstance(event, MessageDelivered) for event in self.events):
            raise ValueError("message delivery phase requires delivery events")
        if canonical_event_order(self.events) != self.events:
            raise ValueError("message delivery events must be canonically ordered")


def emit_message_delivery_events(state: MissionState) -> MessageDeliveryPhase:
    """Emit each current-tick delivery in canonical message-ledger order."""
    if not isinstance(state, MissionState):
        raise TypeError("message delivery requires mission state")
    next_state = state
    events: list[MessageDelivered] = []
    for message in state.messages.messages:
        if message.delivery_tick != state.tick:
            continue
        event_id, id_allocator = next_state.id_allocator.allocate_event()
        next_state = replace(next_state, id_allocator=id_allocator)
        events.append(
            MessageDelivered(
                EventHeader(event_id, state.tick, (message.send_event_id,)),
                message,
            )
        )
    return MessageDeliveryPhase(next_state, tuple(events))


def message_sent_event(message: Message) -> MessageSent:
    """Materialise the event carried by one atomically allocated message send."""
    if not isinstance(message, Message):
        raise TypeError("message send event requires a message")
    return MessageSent(
        EventHeader(message.send_event_id, message.send_tick, message.provenance_event_ids),
        message,
    )
