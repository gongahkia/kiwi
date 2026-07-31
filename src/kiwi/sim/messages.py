"""Typed immutable message values and canonical inbox observations."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EntityId, EventId, IdAllocator, MessageId
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


@dataclass(frozen=True, slots=True)
class MessageLedger:
    """Canonical live messages plus the next globally ordered send sequence."""

    messages: tuple[Message, ...] = ()
    next_sequence: int = 0

    def __post_init__(self) -> None:
        if not isinstance(self.messages, tuple):
            raise ValueError("message ledger entries must be an immutable tuple")
        if not isinstance(self.next_sequence, int) or isinstance(self.next_sequence, bool):
            raise ValueError("message ledger next sequence must be an integer")
        if not 0 <= self.next_sequence <= MAX_AUTHORITY_TICK + 1:
            raise ValueError(
                "message ledger next sequence must fit non-negative signed 64-bit range"
            )
        previous_key: tuple[int, int, int, int] = (0, 0, -1, 0)
        message_ids: tuple[MessageId, ...] = ()
        sequences: tuple[int, ...] = ()
        for message in self.messages:
            if not isinstance(message, Message):
                raise ValueError("message ledger entries must contain messages")
            if message.message_id in message_ids:
                raise ValueError("message ledger entries must have unique message IDs")
            if message.sequence in sequences:
                raise ValueError("message ledger entries must have unique sequences")
            if message.sequence >= self.next_sequence:
                raise ValueError("message ledger next sequence must follow every message")
            key = message_order_key(message)
            if key <= previous_key:
                raise ValueError("message ledger entries must use canonical delivery order")
            previous_key = key
            message_ids += (message.message_id,)
            sequences += (message.sequence,)


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


def send_message(
    ledger: MessageLedger,
    id_allocator: IdAllocator,
    sender_entity_id: EntityId,
    recipient_entity_id: EntityId,
    channel: MessageChannel,
    payload: RecordValue,
    send_tick: int,
    expiry_tick: int,
    provenance_event_ids: tuple[EventId, ...],
) -> tuple[MessageLedger, IdAllocator, Message]:
    """Allocate one message that becomes visible at the next authoritative tick."""
    if not isinstance(ledger, MessageLedger):
        raise ValueError("message send requires a message ledger")
    if not isinstance(id_allocator, IdAllocator):
        raise ValueError("message send requires an ID allocator")
    if not isinstance(send_tick, int) or isinstance(send_tick, bool):
        raise ValueError("message send tick must be an integer")
    if not 0 <= send_tick < MAX_AUTHORITY_TICK:
        raise ValueError("message send tick must permit next-tick delivery")
    if ledger.next_sequence > MAX_AUTHORITY_TICK:
        raise ValueError("message send sequence allocation exhausted")
    message_id, next_allocator = id_allocator.allocate_message()
    message = Message(
        message_id=message_id,
        sender_entity_id=sender_entity_id,
        recipient_entity_id=recipient_entity_id,
        channel=channel,
        payload=payload,
        send_tick=send_tick,
        delivery_tick=send_tick + 1,
        expiry_tick=expiry_tick,
        sequence=ledger.next_sequence,
        provenance_event_ids=provenance_event_ids,
    )
    return (
        MessageLedger(
            tuple(sorted((*ledger.messages, message), key=message_order_key)),
            ledger.next_sequence + 1,
        ),
        next_allocator,
        message,
    )


def discard_expired_messages(ledger: MessageLedger, current_tick: int) -> MessageLedger:
    """Drop messages whose inclusive expiry tick precedes the current tick."""
    if not isinstance(ledger, MessageLedger):
        raise ValueError("message expiry requires a message ledger")
    if not isinstance(current_tick, int) or isinstance(current_tick, bool):
        raise ValueError("message expiry tick must be an integer")
    if not 0 <= current_tick <= MAX_AUTHORITY_TICK:
        raise ValueError("message expiry tick must fit non-negative signed 64-bit range")
    retained = tuple(message for message in ledger.messages if message.expiry_tick >= current_tick)
    if retained == ledger.messages:
        return ledger
    return MessageLedger(retained, ledger.next_sequence)


def inbox_for(
    ledger: MessageLedger, recipient_entity_id: EntityId, current_tick: int
) -> InboxObservation:
    """Project one recipient's delivered, unexpired messages in canonical order."""
    if not isinstance(ledger, MessageLedger):
        raise ValueError("inbox projection requires a message ledger")
    if not isinstance(recipient_entity_id, EntityId):
        raise ValueError("inbox projection requires a recipient entity ID")
    if not isinstance(current_tick, int) or isinstance(current_tick, bool):
        raise ValueError("inbox projection tick must be an integer")
    if not 0 <= current_tick <= MAX_AUTHORITY_TICK:
        raise ValueError("inbox projection tick must fit non-negative signed 64-bit range")
    return InboxObservation(
        tuple(
            message
            for message in ledger.messages
            if message.recipient_entity_id == recipient_entity_id
            and message.delivery_tick <= current_tick <= message.expiry_tick
        )
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
