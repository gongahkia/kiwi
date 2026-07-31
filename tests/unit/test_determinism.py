from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import EventId
from kiwi.dsl.runtime_values import RecordValue, StringValue
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandSource, SignalName
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactSighting,
    apply_contact_sightings,
)
from kiwi.sim.determinism import (
    compare_headless_runs,
    first_canonical_state_difference,
    run_determinism_harness,
)
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.memory import PolicyMemoryStore
from kiwi.sim.messages import MessageChannel, send_message
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.signals import SignalObservation, SignalStore
from kiwi.sim.snapshot import capture_authority_snapshot
from kiwi.sim.state import MissionPhase, MissionState, MovementAction, add_entity


def test_determinism_harness_repeats_checkpoint_hashes_exactly() -> None:
    report = run_determinism_harness(
        MissionState(),
        FixedTickClock(TickRate.HZ_30),
        3,
        checkpoint_interval=2,
    )

    assert report.matches
    assert report.divergence is None
    assert tuple(snapshot.tick for snapshot in report.expected.checkpoints) == (0, 2, 3)
    assert report.expected.checkpoints == report.actual.checkpoints


def test_differential_report_uses_first_canonical_entity_path() -> None:
    expected, _ = add_entity(
        MissionState(),
        WorldPosition(WorldSubunits(1_000), WorldSubunits(2_000)),
    )
    actual = replace(
        expected,
        entities=(
            replace(
                expected.entities[0],
                position=WorldPosition(WorldSubunits(1_001), WorldSubunits(2_000)),
            ),
        ),
    )

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "entities/0/position/x"
    assert difference.expected == "1000"
    assert difference.actual == "1001"


def test_differential_report_includes_policy_memory_in_canonical_order() -> None:
    expected, entity = add_entity(
        MissionState(), WorldPosition(WorldSubunits(1_000), WorldSubunits(2_000))
    )
    actual = replace(
        expected,
        policy_memory=PolicyMemoryStore().with_memory(
            entity.entity_id,
            RecordValue("Memory", ("label",), (StringValue("ready"),)),
        ),
    )

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "policy_memory/count"
    assert difference.expected == "0"
    assert difference.actual == "1"


def test_differential_report_includes_contacts_in_canonical_order() -> None:
    expected, owner = add_entity(
        MissionState(), WorldPosition(WorldSubunits(1_000), WorldSubunits(2_000))
    )
    evidence_event_id, allocator = expected.id_allocator.allocate_event()
    contacts, allocator = apply_contact_sightings(
        expected.contacts,
        allocator,
        expected.tick,
        (
            ContactSighting(
                owner.entity_id,
                WorldPosition(WorldSubunits(2_000), WorldSubunits(3_000)),
                WorldSubunits(250),
                ContactConfidence(7_500),
                _contact_provenance(evidence_event_id),
            ),
        ),
    )
    actual = replace(expected, contacts=contacts, id_allocator=allocator)

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "contacts/count"
    assert difference.expected == "0"
    assert difference.actual == "1"


def test_differential_report_includes_contact_field_evidence() -> None:
    state, owner = add_entity(
        MissionState(), WorldPosition(WorldSubunits(1_000), WorldSubunits(2_000))
    )
    first_evidence_event_id, allocator = state.id_allocator.allocate_event()
    second_evidence_event_id, allocator = allocator.allocate_event()
    contacts, allocator = apply_contact_sightings(
        state.contacts,
        allocator,
        state.tick,
        (
            ContactSighting(
                owner.entity_id,
                WorldPosition(WorldSubunits(2_000), WorldSubunits(3_000)),
                WorldSubunits(250),
                ContactConfidence(7_500),
                _contact_provenance(first_evidence_event_id),
            ),
        ),
    )
    expected = replace(state, contacts=contacts, id_allocator=allocator)
    contact = expected.contacts.estimates[0]
    changed_provenance = ContactProvenance(
        (
            *contact.provenance.fields[:2],
            ContactFieldProvenance(ContactField.CONFIDENCE, (second_evidence_event_id,)),
            contact.provenance.fields[3],
        )
    )
    actual = replace(
        expected,
        contacts=replace(
            expected.contacts,
            estimates=(replace(contact, provenance=changed_provenance),),
        ),
    )

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "contacts/0/provenance/confidence/evidence_event_ids/0"
    assert difference.expected == "1"
    assert difference.actual == "2"


def test_differential_report_includes_message_ledger_in_canonical_order() -> None:
    initial, sender = add_entity(
        MissionState(tick=4), WorldPosition(WorldSubunits(1_000), WorldSubunits(2_000))
    )
    state, recipient = add_entity(
        initial, WorldPosition(WorldSubunits(3_000), WorldSubunits(4_000))
    )
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    expected = replace(state, id_allocator=allocator)
    sent = send_message(
        expected.messages,
        expected.id_allocator,
        sender.entity_id,
        recipient.entity_id,
        MessageChannel.RADIO,
        RecordValue("Status", ("label",), (StringValue("ready"),)),
        3,
        5,
        (evidence_event_id,),
    )
    actual = replace(expected, messages=sent.ledger, id_allocator=sent.id_allocator)

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "messages/next_sequence"
    assert difference.expected == "0"
    assert difference.actual == "1"


def test_differential_report_includes_current_signals_in_canonical_order() -> None:
    state, entity = add_entity(
        MissionState(tick=4), WorldPosition(WorldSubunits(1_000), WorldSubunits(2_000))
    )
    event_id, allocator = state.id_allocator.allocate_event()
    expected = replace(state, id_allocator=allocator)
    actual = replace(
        expected,
        signals=SignalStore(
            (
                SignalObservation(
                    SignalName("hold"),
                    4,
                    0,
                    CommandSource.PLAYER,
                    entity.entity_id,
                    event_id,
                ),
            )
        ),
    )

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "signals/count"
    assert difference.expected == "0"
    assert difference.actual == "1"


def _contact_provenance(event_id: EventId) -> ContactProvenance:
    return ContactProvenance(
        tuple(ContactFieldProvenance(field, (event_id,)) for field in ContactField)
    )


def test_differential_report_includes_map_geometry_in_canonical_order() -> None:
    expected = MissionState(
        map_geometry=MapGeometry(
            WorldRectangle(WorldSubunits(0), WorldSubunits(0), WorldSubunits(10), WorldSubunits(10))
        )
    )
    actual = replace(
        expected,
        map_geometry=MapGeometry(
            WorldRectangle(WorldSubunits(1), WorldSubunits(0), WorldSubunits(10), WorldSubunits(10))
        ),
    )

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "map_geometry/bounds/minimum_x"
    assert difference.expected == "0"
    assert difference.actual == "1"


def test_differential_report_includes_future_movement_waypoints() -> None:
    geometry = MapGeometry(
        WorldRectangle(
            WorldSubunits(-1_000), WorldSubunits(-1_000), WorldSubunits(1_000), WorldSubunits(1_000)
        )
    )
    start = WorldPosition(WorldSubunits(0), WorldSubunits(0))
    expected, entity = add_entity(MissionState(map_geometry=geometry), start)
    expected_path = Path(
        PathQuery(geometry, start, WorldPosition(WorldSubunits(100), WorldSubunits(200))),
        (
            start,
            WorldPosition(WorldSubunits(100), WorldSubunits(0)),
            WorldPosition(WorldSubunits(100), WorldSubunits(200)),
        ),
    )
    actual_path = Path(
        PathQuery(geometry, start, WorldPosition(WorldSubunits(200), WorldSubunits(200))),
        (
            start,
            WorldPosition(WorldSubunits(100), WorldSubunits(0)),
            WorldPosition(WorldSubunits(200), WorldSubunits(200)),
        ),
    )
    expected = replace(
        expected, movement_actions=(MovementAction(entity.entity_id, expected_path),)
    )
    actual = replace(expected, movement_actions=(MovementAction(entity.entity_id, actual_path),))

    difference = first_canonical_state_difference(expected, actual)

    assert difference is not None
    assert difference.path == "movement_actions/0/waypoints/2/x"
    assert difference.expected == "100"
    assert difference.actual == "200"


def test_run_comparison_reports_first_divergent_checkpoint() -> None:
    expected_state = MissionState(tick=1)
    actual_state = replace(expected_state, phase=MissionPhase.ACTIVE)
    expected = HeadlessRun(
        expected_state,
        (),
        (capture_authority_snapshot(expected_state),),
    )
    actual = HeadlessRun(
        actual_state,
        (),
        (capture_authority_snapshot(actual_state),),
    )

    divergence = compare_headless_runs(expected, actual)

    assert divergence is not None
    assert divergence.tick == 1
    assert divergence.difference.path == "phase"
    assert divergence.expected_hash != divergence.actual_hash


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: run_headless(
                MissionState(),
                FixedTickClock(TickRate.HZ_30),
                1,
                checkpoint_interval=0,
            ),
            "positive integer",
        ),
        (
            lambda: first_canonical_state_difference(object(), MissionState()),  # type: ignore[arg-type]
            "mission states",
        ),
    ),
)
def test_determinism_helpers_reject_invalid_inputs(factory: object, message: str) -> None:
    with pytest.raises((TypeError, ValueError), match=message):
        factory()  # type: ignore[operator]
