from __future__ import annotations

from dataclasses import replace
from pathlib import Path

from kiwi.domain.geometry import WorldPosition, WorldSubunits, distance_from_world_subunits
from kiwi.domain.ids import ContactId, EntityId, EventId
from kiwi.domain.quantities import Quantity, quantity_from_literal
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import IntegerValue, QuantityValue, RecordValue, StringValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.communication import message_sent_event
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactEstimate,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactStore,
    advance_contacts,
)
from kiwi.sim.events import IntentionEmitted, MessageDelivered, PolicyEvaluated
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.intentions import WaitIntention
from kiwi.sim.messages import MessageChannel, send_message
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.state import MissionState, add_entity

FIXTURE_PATH = (
    Path(__file__).resolve().parents[1] / "fixtures" / "policies" / "contact_option_policy.dtr"
)
MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_missing_contact_fixture_safely_selects_the_none_branch() -> None:
    state, entity = add_entity(
        MissionState(tick=4), WorldPosition(WorldSubunits(0), WorldSubunits(0))
    )

    result = _run_fixture(state, entity.entity_id)

    evaluation = _policy_evaluation(result)
    assert evaluation.validation.succeeded
    assert evaluation.validation.evaluation.observation.nearest_contact is None
    assert _wait_duration(result) == quantity_from_literal(1, "s")


def test_stale_contact_fixture_selects_some_deterministically() -> None:
    state, entity = add_entity(
        MissionState(tick=1), WorldPosition(WorldSubunits(0), WorldSubunits(0))
    )
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    contact_id, allocator = allocator.allocate_contact()
    contact = ContactEstimate(
        contact_id,
        entity.entity_id,
        WorldPosition(WorldSubunits(2_000), WorldSubunits(0)),
        WorldSubunits(300),
        ContactConfidence(7_500),
        1,
        _contact_provenance(evidence_event_id),
    )
    stale_state = replace(
        state,
        tick=4,
        contacts=advance_contacts(ContactStore((contact,), lifecycle_tick=1), 4),
        id_allocator=allocator,
    )

    first = _run_fixture(stale_state, entity.entity_id)
    second = _run_fixture(stale_state, entity.entity_id)
    observation = _policy_evaluation(first).validation.evaluation.observation

    assert first.events == second.events
    assert first.checkpoints == second.checkpoints
    assert hash_canonical_state(first.state) == hash_canonical_state(second.state)
    assert observation.nearest_contact is not None
    assert observation.nearest_contact.age_at(4).ticks == 3
    assert observation.nearest_contact.confidence == ContactConfidence(7_200)
    assert observation.nearest_contact.uncertainty_radius == WorldSubunits(600)
    assert _wait_duration(first) == quantity_from_literal(2, "s")


def test_relayed_contact_report_fixture_remains_an_inbox_message() -> None:
    initial, sender = add_entity(
        MissionState(tick=4), WorldPosition(WorldSubunits(-1_000), WorldSubunits(0))
    )
    state, recipient = add_entity(initial, WorldPosition(WorldSubunits(0), WorldSubunits(0)))
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    sent = send_message(
        state.messages,
        allocator,
        sender.entity_id,
        recipient.entity_id,
        MessageChannel.RADIO,
        _contact_report(),
        send_tick=3,
        expiry_tick=6,
        provenance_event_ids=(evidence_event_id,),
    )
    state = replace(state, messages=sent.ledger, id_allocator=sent.id_allocator)

    result = _run_fixture(state, recipient.entity_id)
    sent_event = message_sent_event(sent.message)
    delivery = next(event for event in result.events if isinstance(event, MessageDelivered))
    observation = _policy_evaluation(result).validation.evaluation.observation

    assert sent_event.header.parent_event_ids == (evidence_event_id,)
    assert delivery.message == sent.message
    assert delivery.header.parent_event_ids == (sent_event.header.event_id,)
    assert observation.inbox.messages == (sent.message,)
    assert observation.nearest_contact is None
    assert result.state.contacts.estimates == ()
    assert _wait_duration(result) == quantity_from_literal(1, "s")


def _run_fixture(state: MissionState, entity_id: EntityId) -> HeadlessRun:
    source = SourceFile(
        SourceFileId("tests/fixtures/policies/contact_option_policy.dtr"),
        FIXTURE_PATH.read_text(encoding="utf-8"),
    )
    artifact = _compile(source)
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity_id,
                artifact,
                FunctionId(0),
                MEMORY_SCHEMA,
                RecordValue("Memory", ("label",), (StringValue("ready"),)),
            ),
        )
    )
    return run_headless(
        state,
        FixedTickClock(TickRate.HZ_30),
        1,
        (StartMission(CommandHeader(state.tick, 0, CommandSource.SCENARIO)),),
        checkpoint_interval=1,
        policy_bindings=bindings,
    )


def _policy_evaluation(result: HeadlessRun) -> PolicyEvaluated:
    return next(event for event in result.events if isinstance(event, PolicyEvaluated))


def _wait_duration(result: HeadlessRun) -> Quantity:
    emitted = next(event for event in result.events if isinstance(event, IntentionEmitted))
    assert isinstance(emitted.candidate.intention, WaitIntention)
    return emitted.candidate.intention.duration


def _contact_provenance(event_id: EventId) -> ContactProvenance:
    return ContactProvenance(
        tuple(ContactFieldProvenance(field, (event_id,)) for field in ContactField)
    )


def _contact_report() -> RecordValue:
    return RecordValue(
        "ContactReport",
        ("age_ticks", "confidence_basis_points", "estimated_position", "uncertainty_radius"),
        (
            IntegerValue(3),
            IntegerValue(7_200),
            RecordValue(
                "Position",
                ("x", "y"),
                (
                    QuantityValue(distance_from_world_subunits(WorldSubunits(2_000))),
                    QuantityValue(distance_from_world_subunits(WorldSubunits(0))),
                ),
            ),
            QuantityValue(distance_from_world_subunits(WorldSubunits(600))),
        ),
    )


def _compile(source: SourceFile) -> CompiledArtifact:
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
