from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits, distance_from_world_subunits
from kiwi.domain.ids import EntityId
from kiwi.dsl.runtime_values import IntegerValue, ListValue, QuantityValue, RecordValue
from kiwi.sim.messages import (
    INBOX_OBSERVATION_RECORD_TYPE,
    InboxObservation,
    MessageChannel,
    send_message,
)
from kiwi.sim.observations import (
    OBSERVATION_RECORD_TYPE,
    OBSERVATION_SCHEMA_VERSION,
    POSITION_RECORD_TYPE,
    SELF_OBSERVATION_RECORD_TYPE,
    RuntimeObservation,
    SelfObservation,
    build_runtime_observations,
    observation_runtime_value,
)
from kiwi.sim.state import MissionState, add_entity


def test_runtime_observation_converts_to_the_versioned_closed_dsl_layout() -> None:
    observation = RuntimeObservation(
        SelfObservation(EntityId(4), WorldPosition(WorldSubunits(-2_000), WorldSubunits(500))),
        tick=9,
    )

    value = observation_runtime_value(observation)

    assert OBSERVATION_SCHEMA_VERSION == 3
    assert value.type_name == OBSERVATION_RECORD_TYPE
    assert value.field_names == ("inbox", "self", "signals", "tick")
    inbox_value = value.field_value("inbox")
    assert isinstance(inbox_value, RecordValue)
    assert inbox_value.type_name == INBOX_OBSERVATION_RECORD_TYPE
    assert inbox_value.field_names == ("messages",)
    assert inbox_value.field_value("messages") == ListValue(())
    assert value.field_value("signals") == ListValue(())
    self_value = value.field_value("self")
    assert isinstance(self_value, RecordValue)
    assert self_value.type_name == SELF_OBSERVATION_RECORD_TYPE
    assert self_value.field_names == ("entity_id", "position")
    assert self_value.field_value("entity_id") == IntegerValue(4)
    position_value = self_value.field_value("position")
    assert isinstance(position_value, RecordValue)
    assert position_value.type_name == POSITION_RECORD_TYPE
    assert position_value.field_names == ("x", "y")
    assert position_value.field_value("x") == QuantityValue(
        distance_from_world_subunits(WorldSubunits(-2_000))
    )
    assert position_value.field_value("y") == QuantityValue(
        distance_from_world_subunits(WorldSubunits(500))
    )
    assert value.field_value("tick") == IntegerValue(9)


def test_runtime_observations_snapshot_pre_evaluation_state_in_entity_id_order() -> None:
    first_state, first = add_entity(
        MissionState(tick=7), WorldPosition(WorldSubunits(1), WorldSubunits(2))
    )
    state, second = add_entity(first_state, WorldPosition(WorldSubunits(-3), WorldSubunits(4)))

    observations = build_runtime_observations(state)
    successor = replace(
        state,
        tick=8,
        entities=(
            state.entities[0],
            replace(second, position=WorldPosition(WorldSubunits(9), WorldSubunits(10))),
        ),
    )

    assert observations == (
        RuntimeObservation(SelfObservation(first.entity_id, first.position), 7),
        RuntimeObservation(SelfObservation(second.entity_id, second.position), 7),
    )
    assert observations[1].self_observation.position != successor.entities[1].position


def test_runtime_observations_project_only_each_owner_delivered_messages() -> None:
    first_state, sender = add_entity(
        MissionState(tick=4), WorldPosition(WorldSubunits(1), WorldSubunits(2))
    )
    state, recipient = add_entity(first_state, WorldPosition(WorldSubunits(-3), WorldSubunits(4)))
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    sent = send_message(
        state.messages,
        allocator,
        sender.entity_id,
        recipient.entity_id,
        MessageChannel.RADIO,
        RecordValue("Status", ("label",), (IntegerValue(1),)),
        3,
        5,
        (evidence_event_id,),
    )
    state = replace(state, messages=sent.ledger, id_allocator=sent.id_allocator)

    observations = build_runtime_observations(state)

    assert observations[0].inbox == InboxObservation()
    assert observations[1].inbox == InboxObservation((sent.message,))


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: SelfObservation(EntityId(1), object()),  # type: ignore[arg-type]
            "world position",
        ),
        (
            lambda: RuntimeObservation(object(), 0),  # type: ignore[arg-type]
            "self observation",
        ),
        (
            lambda: RuntimeObservation(
                SelfObservation(EntityId(1), WorldPosition(WorldSubunits(0), WorldSubunits(0))),
                -1,
            ),
            "non-negative",
        ),
        (lambda: observation_runtime_value(object()), "RuntimeObservation"),  # type: ignore[arg-type]
        (lambda: build_runtime_observations(object()), "mission state"),  # type: ignore[arg-type]
    ),
)
def test_runtime_observation_schema_rejects_invalid_values(factory: object, message: str) -> None:
    with pytest.raises((TypeError, ValueError), match=message):
        factory()  # type: ignore[operator]
