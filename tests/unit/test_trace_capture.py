from __future__ import annotations

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EventId, IntentionId
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
from kiwi.sim.hashing import StateHash, hash_canonical_state
from kiwi.sim.policies import (
    PolicyBinding,
    PolicyBindings,
    invoke_policies,
    validate_policy_evaluations,
)
from kiwi.sim.policy_events import PolicyEventPhase, emit_policy_events
from kiwi.sim.state import MissionState, add_entity
from kiwi.trace.capture import capture_policy_lifecycle_trace
from kiwi.trace.model import (
    IntentionResolutionTrace,
    IntentionTrace,
    TraceEdgeKind,
    TraceLevel,
    TraceResolutionStatus,
)

MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_policy_lifecycle_trace_links_origins_to_validation_and_arbitration() -> None:
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

    trace = capture_policy_lifecycle_trace(phase, hash_canonical_state(phase.state))

    intentions = tuple(record for record in trace.records if isinstance(record, IntentionTrace))
    resolutions = tuple(
        record for record in trace.records if isinstance(record, IntentionResolutionTrace)
    )
    assert trace.level is TraceLevel.DECISION
    assert tuple(record.origin for record in intentions) == tuple(
        decision.candidate.origin for decision in arbitration.decisions
    )
    assert tuple(
        (
            record.intention_id,
            record.status,
            record.reason_code,
            record.competing_intention_ids,
            record.world_event_ids,
        )
        for record in resolutions
    ) == (
        (
            IntentionId(1),
            TraceResolutionStatus.SELECTED,
            None,
            (),
            (EventId(1), EventId(3), EventId(4)),
        ),
        (
            IntentionId(2),
            TraceResolutionStatus.REJECTED,
            "channel_occupied",
            (IntentionId(1),),
            (EventId(1), EventId(5), EventId(6)),
        ),
        (
            IntentionId(3),
            TraceResolutionStatus.SELECTED,
            None,
            (),
            (EventId(2), EventId(7), EventId(8)),
        ),
        (
            IntentionId(4),
            TraceResolutionStatus.REJECTED,
            "channel_occupied",
            (IntentionId(3),),
            (EventId(2), EventId(9), EventId(10)),
        ),
    )
    assert tuple(
        (edge.source_node_id.value, edge.target_node_id.value, edge.kind) for edge in trace.edges
    ) == (
        (1, 5, TraceEdgeKind.VALIDATED_BY),
        (2, 6, TraceEdgeKind.REJECTED_BECAUSE),
        (1, 6, TraceEdgeKind.SELECTED_OVER),
        (3, 7, TraceEdgeKind.VALIDATED_BY),
        (4, 8, TraceEdgeKind.REJECTED_BECAUSE),
        (3, 8, TraceEdgeKind.SELECTED_OVER),
    )


def test_policy_lifecycle_trace_rejects_a_hash_for_another_authority_state() -> None:
    phase = _policy_event_phase()

    with pytest.raises(ValueError, match="must match the event phase state"):
        capture_policy_lifecycle_trace(phase, StateHash(b"x" * 32))


def _policy_event_phase() -> PolicyEventPhase:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    artifact = _two_wait_policy_artifact()
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id, artifact, FunctionId(0), MEMORY_SCHEMA, _memory("initial")
            ),
        )
    )
    validations = validate_policy_evaluations(invoke_policies(state, bindings), bindings)
    return emit_policy_events(validations, arbitrate_intentions(validations, bindings))


def _memory(label: str) -> RecordValue:
    return RecordValue("Memory", ("label",), (StringValue(label),))


def _two_wait_policy_artifact() -> CompiledArtifact:
    source = SourceFile(
        SourceFileId("trace-capture-policy.dtr"),
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
