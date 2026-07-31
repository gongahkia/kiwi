"""Typed immutable message values and canonical inbox observations."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EntityId, EventId, MessageId
from kiwi.dsl.runtime_values import IntegerValue, ListValue, RecordValue, StringValue
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.memory import is_persistable_memory_value

MAX_MESSAGE_PROVENANCE_EVENTS = 64
MESSAGE_RECORD_TYPE = "Message"
INBOX_OBSERVATION_RECORD_TYPE = "InboxObservation"


class MessageChannel(StrEnum):
    """The closed initial message transport channels."""

    RADIO = "radio"


@dataclass(frozen=True, slots=True)
class Message:
    """One typed, addressed, provenance-linked immutable message value."""

    message_id: MessageId
    sender_entity_id: EntityId
    recipient_entity_id: EntityId
    channel: MessageChannel
    payload: RecordValue
    send_tick: int
    delivery_tick: int
    expiry_tick: int
    sequence: int
    provenance_event_ids: tuple[EventId, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.message_id, MessageId):
            raise ValueError("message requires a message ID")
        if not isinstance(self.sender_entity_id, EntityId):
            raise ValueError("message requires a sender entity ID")
        if not isinstance(self.recipient_entity_id, EntityId):
            raise ValueError("message requires a recipient entity ID")
        if not isinstance(self.channel, MessageChannel):
            raise ValueError("message requires a message channel")
        if not isinstance(self.payload, RecordValue) or not is_persistable_memory_value(
            self.payload
        ):
            raise ValueError("message payload must be a persistable typed record")
        for tick, label in (
            (self.send_tick, "send"),
            (self.delivery_tick, "delivery"),
            (self.expiry_tick, "expiry"),
        ):
            if not isinstance(tick, int) or isinstance(tick, bool):
                raise ValueError(f"message {label} tick must be an integer")
            if not 0 <= tick <= MAX_AUTHORITY_TICK:
                raise ValueError(f"message {label} tick must fit non-negative signed 64-bit range")
        if not self.send_tick <= self.delivery_tick <= self.expiry_tick:
            raise ValueError("message ticks must satisfy send, delivery, then expiry order")
        if not isinstance(self.sequence, int) or isinstance(self.sequence, bool):
            raise ValueError("message sequence must be an integer")
        if not 0 <= self.sequence <= MAX_AUTHORITY_TICK:
            raise ValueError("message sequence must fit non-negative signed 64-bit range")
        if not isinstance(self.provenance_event_ids, tuple):
            raise ValueError("message provenance IDs must be an immutable tuple")
        if not 1 <= len(self.provenance_event_ids) <= MAX_MESSAGE_PROVENANCE_EVENTS:
            raise ValueError("message provenance IDs must contain between one and 64 event IDs")
        previous_id = 0
        for event_id in self.provenance_event_ids:
            if not isinstance(event_id, EventId):
                raise ValueError("message provenance IDs must contain event IDs")
            if event_id.value <= previous_id:
                raise ValueError("message provenance IDs must be unique and ascending")
            previous_id = event_id.value


@dataclass(frozen=True, slots=True)
class InboxObservation:
    """An immutable delivery-ordered inbox without writable shared state."""

    messages: tuple[Message, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.messages, tuple):
            raise ValueError("inbox messages must be an immutable tuple")
        previous_key: tuple[int, int, int, int] = (0, 0, -1, 0)
        message_ids: tuple[MessageId, ...] = ()
        for message in self.messages:
            if not isinstance(message, Message):
                raise ValueError("inbox messages must contain messages")
            if message.message_id in message_ids:
                raise ValueError("inbox messages must have unique message IDs")
            key = message_order_key(message)
            if key <= previous_key:
                raise ValueError("inbox messages must use canonical delivery order")
            previous_key = key
            message_ids += (message.message_id,)


def message_order_key(message: Message) -> tuple[int, int, int, int]:
    """Return the explicit delivery key used by inboxes and future queues."""
    if not isinstance(message, Message):
        raise ValueError("message ordering requires a message")
    return (
        message.delivery_tick,
        message.sender_entity_id.value,
        message.sequence,
        message.message_id.value,
    )


def message_runtime_value(message: Message) -> RecordValue:
    """Convert one typed authority message into a closed DSL record."""
    if not isinstance(message, Message):
        raise TypeError("message runtime value requires a Message")
    return RecordValue(
        MESSAGE_RECORD_TYPE,
        (
            "channel",
            "delivery_tick",
            "expiry_tick",
            "message_id",
            "payload",
            "recipient_entity_id",
            "send_tick",
            "sender_entity_id",
            "sequence",
        ),
        (
            StringValue(message.channel.value),
            IntegerValue(message.delivery_tick),
            IntegerValue(message.expiry_tick),
            IntegerValue(message.message_id.value),
            message.payload,
            IntegerValue(message.recipient_entity_id.value),
            IntegerValue(message.send_tick),
            IntegerValue(message.sender_entity_id.value),
            IntegerValue(message.sequence),
        ),
    )


def inbox_runtime_value(inbox: InboxObservation) -> RecordValue:
    """Convert one immutable inbox to its closed DSL record layout."""
    if not isinstance(inbox, InboxObservation):
        raise TypeError("inbox runtime value requires an InboxObservation")
    return RecordValue(
        INBOX_OBSERVATION_RECORD_TYPE,
        ("messages",),
        (ListValue(tuple(message_runtime_value(message) for message in inbox.messages)),),
    )
