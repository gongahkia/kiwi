from __future__ import annotations

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EventId, IdKind, IntentionId
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import RecordValue, StringValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.sim.arbitration import arbitrate_intentions
from kiwi.sim.events import (
    IntentionEmitted,
    IntentionRejected,
    IntentionSelected,
    PolicyEvaluated,
)
from kiwi.sim.policies import (
    PolicyBinding,
    PolicyBindings,
    PolicyValidationCode,
    invoke_policies,
    validate_policy_evaluations,
)
from kiwi.sim.policy_events import emit_policy_events
from kiwi.sim.state import MissionState, add_entity

MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_policy_event_emission_retains_canonical_causal_order() -> None:
    first_state, first = add_entity(
        MissionState(tick=5), WorldPosition(WorldSubunits(1), WorldSubunits(2))
    )
    state, second = add_entity(first_state, WorldPosition(WorldSubunits(3), WorldSubunits(4)))
    artifact = _two_wait_policy_artifact()
    bindings = PolicyBindings(
        (
            PolicyBinding(
                first.entity_id, artifact, FunctionId(0), MEMORY_SCHEMA, _memory("first")
            ),
            PolicyBinding(
                second.entity_id, artifact, FunctionId(0), MEMORY_SCHEMA, _memory("second")
            ),
        )
    )
    validations = validate_policy_evaluations(invoke_policies(state, bindings), bindings)
    arbitration = arbitrate_intentions(validations, bindings)

    phase = emit_policy_events(validations, arbitration)

    assert tuple(type(event) for event in phase.events) == (
        PolicyEvaluated,
        PolicyEvaluated,
        IntentionEmitted,
        IntentionSelected,
        IntentionEmitted,
        IntentionRejected,
        IntentionEmitted,
        IntentionSelected,
        IntentionEmitted,
        IntentionRejected,
    )
    assert tuple(event.header.event_id for event in phase.events) == tuple(
        EventId(index) for index in range(1, 11)
    )
    assert phase.events[2].header.parent_event_ids == (EventId(1),)
    assert phase.events[3].header.parent_event_ids == (EventId(3),)
    assert phase.events[4].header.parent_event_ids == (EventId(1),)
    assert phase.events[5].header.parent_event_ids == (EventId(5),)
    assert phase.events[6].header.parent_event_ids == (EventId(2),)
    assert phase.events[7].header.parent_event_ids == (EventId(7),)
    assert phase.events[8].header.parent_event_ids == (EventId(2),)
    assert phase.events[9].header.parent_event_ids == (EventId(9),)
    first_rejection = phase.events[5]
    assert isinstance(first_rejection, IntentionRejected)
    assert first_rejection.resolution.competing_intention_ids == (IntentionId(1),)
    emitted = tuple(event for event in phase.events if isinstance(event, IntentionEmitted))
    assert tuple(event.candidate.origin for event in emitted) == tuple(
        decision.candidate.origin for decision in arbitration.decisions
    )
    assert phase.state.id_allocator.next_ids[int(IdKind.EVENT)] == 11


def test_policy_event_emission_retains_failed_evaluation_without_candidates() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    artifact = _two_wait_policy_artifact()
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                artifact,
                FunctionId(0),
                MEMORY_SCHEMA,
                _memory("initial"),
                available_capabilities=(),
            ),
        )
    )
    validations = validate_policy_evaluations(invoke_policies(state, bindings), bindings)
    arbitration = arbitrate_intentions(validations, bindings)

    phase = emit_policy_events(validations, arbitration)

    assert len(phase.events) == 1
    assert isinstance(phase.events[0], PolicyEvaluated)
    assert phase.events[0].validation.failure is not None
    assert phase.events[0].validation.failure.code is PolicyValidationCode.CAPABILITY
    assert arbitration.decisions == ()
    assert phase.state.id_allocator.next_ids[int(IdKind.EVENT)] == 2
    assert phase.state.id_allocator.next_ids[int(IdKind.INTENTION)] == 1


def _memory(label: str) -> RecordValue:
    return RecordValue("Memory", ("label",), (StringValue(label),))


def _two_wait_policy_artifact() -> CompiledArtifact:
    source = SourceFile(
        SourceFileId("policy.dtr"),
        "type SelfObservation = { entity_id: Int, position: Position }\n"
        "type Observation = { self: SelfObservation, tick: Int }\n"
        "type Memory = { label: String }\n"
        "type Wait = { duration: Duration }\n"
        "type Decision = { intentions: List<Wait>, memory: Memory }\n"
        "policy decide(observation: Observation, memory: Memory) -> Decision = "
        "Decision { "
        "intentions = [Wait { duration = 1s }, Wait { duration = 2s }], "
        "memory = memory "
        "}\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
