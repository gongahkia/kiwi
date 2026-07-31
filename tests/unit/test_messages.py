from __future__ import annotations

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EntityId, EventId, MessageId
from kiwi.dsl.runtime_values import IntegerValue, ListValue, RecordValue, StringValue
from kiwi.sim.messages import (
    INBOX_OBSERVATION_RECORD_TYPE,
    MESSAGE_RECORD_TYPE,
    InboxObservation,
    Message,
    MessageChannel,
    inbox_runtime_value,
    message_order_key,
    message_runtime_value,
)
from kiwi.sim.observations import RuntimeObservation, SelfObservation, observation_runtime_value


def test_typed_message_projects_to_a_closed_inbox_observation() -> None:
    message = _message(MessageId(3), EntityId(1), EntityId(2), delivery_tick=4, sequence=7)
    inbox = InboxObservation((message,))
    observation = RuntimeObservation(
        SelfObservation(EntityId(2), WorldPosition(WorldSubunits(0), WorldSubunits(0))),
        tick=4,
        inbox=inbox,
    )

    message_value = message_runtime_value(message)
    inbox_value = inbox_runtime_value(inbox)
    observation_value = observation_runtime_value(observation)

    assert message_order_key(message) == (4, 1, 7, 3)
    assert message_value == RecordValue(
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
            StringValue("radio"),
            IntegerValue(4),
            IntegerValue(5),
            IntegerValue(3),
            _payload(),
            IntegerValue(2),
            IntegerValue(3),
            IntegerValue(1),
            IntegerValue(7),
        ),
    )
    assert inbox_value.type_name == INBOX_OBSERVATION_RECORD_TYPE
    assert inbox_value.field_value("messages") == ListValue((message_value,))
    observation_inbox = observation_value.field_value("inbox")
    assert observation_inbox == inbox_value


def test_inbox_requires_canonical_delivery_order_and_unique_message_ids() -> None:
    first = _message(MessageId(1), EntityId(1), EntityId(3), delivery_tick=4, sequence=1)
    second = _message(MessageId(2), EntityId(2), EntityId(3), delivery_tick=4, sequence=0)
    duplicate = _message(MessageId(1), EntityId(2), EntityId(3), delivery_tick=5, sequence=0)

    assert InboxObservation((first, second)).messages == (first, second)
    with pytest.raises(ValueError, match="canonical delivery order"):
        InboxObservation((second, first))
    with pytest.raises(ValueError, match="unique message IDs"):
        InboxObservation((first, duplicate))


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: Message(
                MessageId(1),
                EntityId(1),
                EntityId(2),
                MessageChannel.RADIO,
                IntegerValue(1),  # type: ignore[arg-type]
                1,
                2,
                3,
                0,
                (EventId(1),),
            ),
            "typed record",
        ),
        (
            lambda: Message(
                MessageId(1),
                EntityId(1),
                EntityId(2),
                MessageChannel.RADIO,
                _payload(),
                3,
                2,
                4,
                0,
                (EventId(1),),
            ),
            "send, delivery, then expiry",
        ),
        (
            lambda: Message(
                MessageId(1),
                EntityId(1),
                EntityId(2),
                MessageChannel.RADIO,
                _payload(),
                1,
                2,
                3,
                0,
                (EventId(2), EventId(1)),
            ),
            "unique and ascending",
        ),
        (
            lambda: InboxObservation([]),  # type: ignore[arg-type]
            "immutable tuple",
        ),
        (
            lambda: RuntimeObservation(
                SelfObservation(EntityId(1), WorldPosition(WorldSubunits(0), WorldSubunits(0))),
                4,
                InboxObservation((_message(MessageId(1), EntityId(2), EntityId(3)),)),
            ),
            "belong to its entity",
        ),
        (
            lambda: RuntimeObservation(
                SelfObservation(EntityId(2), WorldPosition(WorldSubunits(0), WorldSubunits(0))),
                3,
                InboxObservation(
                    (_message(MessageId(1), EntityId(1), EntityId(2), delivery_tick=4),)
                ),
            ),
            "delivered and unexpired",
        ),
    ),
)
def test_message_and_inbox_values_reject_invalid_inputs(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def _message(
    message_id: MessageId,
    sender_entity_id: EntityId,
    recipient_entity_id: EntityId,
    *,
    delivery_tick: int = 4,
    sequence: int = 0,
) -> Message:
    return Message(
        message_id,
        sender_entity_id,
        recipient_entity_id,
        MessageChannel.RADIO,
        _payload(),
        3,
        delivery_tick,
        5,
        sequence,
        (EventId(1),),
    )


def _payload() -> RecordValue:
    return RecordValue("Status", ("label",), (StringValue("ready"),))
