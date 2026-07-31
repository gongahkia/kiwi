from __future__ import annotations

from dataclasses import replace

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EventId
from kiwi.dsl.runtime_values import RecordValue, StringValue
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.communication import emit_message_delivery_events, message_sent_event
from kiwi.sim.events import EventKind, MessageDelivered, MessageSent, event_kind
from kiwi.sim.messages import MessageChannel, MessageLedger, send_message
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.state import MissionPhase, MissionState, add_entity


def test_message_events_link_source_send_and_delivery_in_canonical_order() -> None:
    initial, first = add_entity(
        MissionState(tick=4), WorldPosition(WorldSubunits(0), WorldSubunits(0))
    )
    state, second = add_entity(initial, WorldPosition(WorldSubunits(1), WorldSubunits(1)))
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    first_send = send_message(
        MessageLedger(),
        allocator,
        second.entity_id,
        first.entity_id,
        MessageChannel.RADIO,
        _payload(),
        3,
        5,
        (evidence_event_id,),
    )
    second_send = send_message(
        first_send.ledger,
        first_send.id_allocator,
        first.entity_id,
        second.entity_id,
        MessageChannel.RADIO,
        _payload(),
        3,
        5,
        (evidence_event_id,),
    )
    state = replace(state, messages=second_send.ledger, id_allocator=second_send.id_allocator)

    sent = message_sent_event(second_send.message)
    phase = emit_message_delivery_events(state)

    assert isinstance(sent, MessageSent)
    assert event_kind(sent) is EventKind.MESSAGE_SENT
    assert sent.header.event_id == second_send.message.send_event_id
    assert sent.header.parent_event_ids == (evidence_event_id,)
    assert tuple(type(event) for event in phase.events) == (MessageDelivered, MessageDelivered)
    assert tuple(event.header.event_id.value for event in phase.events) == (4, 5)
    assert tuple(event.message.message_id.value for event in phase.events) == (2, 1)
    assert phase.events[0].header.parent_event_ids == (EventId(3),)
    assert phase.events[1].header.parent_event_ids == (EventId(2),)
    assert event_kind(phase.events[0]) is EventKind.MESSAGE_DELIVERED


def test_reducer_emits_current_tick_message_deliveries_before_policy_evaluation() -> None:
    initial, sender = add_entity(
        MissionState(tick=4, phase=MissionPhase.ACTIVE),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
    )
    state, recipient = add_entity(initial, WorldPosition(WorldSubunits(1), WorldSubunits(1)))
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    sent = send_message(
        state.messages,
        allocator,
        sender.entity_id,
        recipient.entity_id,
        MessageChannel.RADIO,
        _payload(),
        3,
        5,
        (evidence_event_id,),
    )
    state = replace(state, messages=sent.ledger, id_allocator=sent.id_allocator)

    result = reduce_one_tick(state, FixedTickClock(TickRate.HZ_30))

    assert result.state.tick == 5
    assert len(result.events) == 1
    assert isinstance(result.events[0], MessageDelivered)
    assert result.events[0].message == sent.message
    assert result.events[0].header.parent_event_ids == (sent.message.send_event_id,)


def _payload() -> RecordValue:
    return RecordValue("Status", ("label",), (StringValue("ready"),))
