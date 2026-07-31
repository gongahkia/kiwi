from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits, distance_from_world_subunits
from kiwi.domain.ids import ContactId, EntityId, EventId
from kiwi.dsl.runtime_values import (
    IntegerValue,
    ListValue,
    OptionNoneValue,
    OptionSomeValue,
    QuantityValue,
    RecordValue,
    StringValue,
)
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactEstimate,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactStore,
)
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)
from kiwi.sim.messages import (
    INBOX_OBSERVATION_RECORD_TYPE,
    InboxObservation,
    MessageChannel,
    send_message,
)
from kiwi.sim.observations import (
    CONTACT_RECORD_TYPE,
    COVER_RECORD_TYPE,
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

    assert OBSERVATION_SCHEMA_VERSION == 5
    assert value.type_name == OBSERVATION_RECORD_TYPE
    assert value.field_names == (
        "inbox",
        "nearest_contact",
        "self",
        "signals",
        "tick",
        "visible_covers",
    )
    inbox_value = value.field_value("inbox")
    assert isinstance(inbox_value, RecordValue)
    assert inbox_value.type_name == INBOX_OBSERVATION_RECORD_TYPE
    assert inbox_value.field_names == ("messages",)
    assert inbox_value.field_value("messages") == ListValue(())
    assert value.field_value("nearest_contact") == OptionNoneValue()
    assert value.field_value("signals") == ListValue(())
    assert value.field_value("visible_covers") == ListValue(())
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


def test_runtime_observations_project_visible_cover_records() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(0), WorldSubunits(0)))
    cover_id, allocator = state.id_allocator.allocate_cover()
    cover = CoverSegment(
        cover_id,
        WorldPosition(WorldSubunits(1_000), WorldSubunits(0)),
        WorldPosition(WorldSubunits(2_000), WorldSubunits(0)),
        CoverHeight.HIGH,
        CoverIntegrity(8_500),
        (CoverSlot(0, WorldPosition(WorldSubunits(1_000), WorldSubunits(-350)), CoverSide.LEFT),),
    )
    state = replace(state, covers=CoverStore((cover,)), id_allocator=allocator)

    observation = build_runtime_observations(state)[0]
    value = observation_runtime_value(observation)

    assert tuple(item.cover_id for item in observation.visible_covers) == (cover_id,)
    assert value.field_value("visible_covers") == ListValue(
        (
            RecordValue(
                COVER_RECORD_TYPE,
                ("cover_id", "end", "height", "integrity_basis_points", "slots", "start"),
                (
                    IntegerValue(cover_id.value),
                    RecordValue(
                        POSITION_RECORD_TYPE,
                        ("x", "y"),
                        (
                            QuantityValue(distance_from_world_subunits(WorldSubunits(2_000))),
                            QuantityValue(distance_from_world_subunits(WorldSubunits(0))),
                        ),
                    ),
                    StringValue("high"),
                    IntegerValue(8_500),
                    ListValue(
                        (
                            RecordValue(
                                "CoverSlot",
                                ("position", "side", "slot_index"),
                                (
                                    RecordValue(
                                        POSITION_RECORD_TYPE,
                                        ("x", "y"),
                                        (
                                            QuantityValue(
                                                distance_from_world_subunits(WorldSubunits(1_000))
                                            ),
                                            QuantityValue(
                                                distance_from_world_subunits(WorldSubunits(-350))
                                            ),
                                        ),
                                    ),
                                    StringValue("left"),
                                    IntegerValue(0),
                                ),
                            ),
                        )
                    ),
                    RecordValue(
                        POSITION_RECORD_TYPE,
                        ("x", "y"),
                        (
                            QuantityValue(distance_from_world_subunits(WorldSubunits(1_000))),
                            QuantityValue(distance_from_world_subunits(WorldSubunits(0))),
                        ),
                    ),
                ),
            ),
        )
    )


def test_runtime_observations_project_one_owner_local_contact_with_field_evidence() -> None:
    state, entity = add_entity(
        MissionState(tick=7), WorldPosition(WorldSubunits(1_000), WorldSubunits(2_000))
    )
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    contact_id, allocator = allocator.allocate_contact()
    contact = ContactEstimate(
        contact_id,
        entity.entity_id,
        WorldPosition(WorldSubunits(2_000), WorldSubunits(2_000)),
        WorldSubunits(300),
        ContactConfidence(7_500),
        4,
        ContactProvenance(
            tuple(ContactFieldProvenance(field, (evidence_event_id,)) for field in ContactField)
        ),
    )
    state = replace(
        state,
        contacts=ContactStore((contact,), lifecycle_tick=7),
        id_allocator=allocator,
    )

    observation = build_runtime_observations(state)[0]
    value = observation_runtime_value(observation)

    assert observation.nearest_contact == contact
    assert observation.nearest_contact.provenance.evidence_for(ContactField.CONFIDENCE) == (
        evidence_event_id,
    )
    nearest_value = value.field_value("nearest_contact")
    assert nearest_value == OptionSomeValue(
        RecordValue(
            CONTACT_RECORD_TYPE,
            (
                "age_ticks",
                "confidence_basis_points",
                "contact_id",
                "estimated_position",
                "uncertainty_radius",
            ),
            (
                IntegerValue(3),
                IntegerValue(7_500),
                IntegerValue(contact_id.value),
                RecordValue(
                    POSITION_RECORD_TYPE,
                    ("x", "y"),
                    (
                        QuantityValue(distance_from_world_subunits(WorldSubunits(2_000))),
                        QuantityValue(distance_from_world_subunits(WorldSubunits(2_000))),
                    ),
                ),
                QuantityValue(distance_from_world_subunits(WorldSubunits(300))),
            ),
        )
    )


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
        (
            lambda: RuntimeObservation(
                SelfObservation(EntityId(1), WorldPosition(WorldSubunits(0), WorldSubunits(0))),
                4,
                nearest_contact=ContactEstimate(
                    ContactId(1),
                    EntityId(2),
                    WorldPosition(WorldSubunits(0), WorldSubunits(0)),
                    WorldSubunits(0),
                    ContactConfidence(1),
                    4,
                    ContactProvenance(
                        tuple(
                            ContactFieldProvenance(field, (EventId(1),)) for field in ContactField
                        )
                    ),
                ),
            ),
            "belong to its entity",
        ),
        (lambda: observation_runtime_value(object()), "RuntimeObservation"),  # type: ignore[arg-type]
        (lambda: build_runtime_observations(object()), "mission state"),  # type: ignore[arg-type]
    ),
)
def test_runtime_observation_schema_rejects_invalid_values(factory: object, message: str) -> None:
    with pytest.raises((TypeError, ValueError), match=message):
        factory()  # type: ignore[operator]
