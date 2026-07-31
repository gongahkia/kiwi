from __future__ import annotations

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import IdKind, IntentionId
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
from kiwi.sim.arbitration import (
    ArbitrationStatus,
    IntentionRejectionReason,
    arbitrate_intentions,
)
from kiwi.sim.policies import (
    PolicyBinding,
    PolicyBindings,
    invoke_policies,
    validate_policy_evaluations,
)
from kiwi.sim.state import MissionState, add_entity

MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_arbitration_selects_first_per_channel_in_entity_and_policy_order() -> None:
    first_state, first = add_entity(
        MissionState(tick=9), WorldPosition(WorldSubunits(1), WorldSubunits(2))
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

    evaluations = invoke_policies(state, bindings)
    validations = validate_policy_evaluations(evaluations, bindings)
    arbitration = arbitrate_intentions(validations, bindings)

    assert tuple(decision.candidate.origin.intention_id for decision in arbitration.decisions) == (
        IntentionId(1),
        IntentionId(2),
        IntentionId(3),
        IntentionId(4),
    )
    issuer_entity_ids = tuple(
        decision.candidate.origin.issuer_entity_id for decision in arbitration.decisions
    )
    assert issuer_entity_ids == (
        first.entity_id,
        first.entity_id,
        second.entity_id,
        second.entity_id,
    )
    assert tuple(decision.status for decision in arbitration.decisions) == (
        ArbitrationStatus.SELECTED,
        ArbitrationStatus.REJECTED,
        ArbitrationStatus.SELECTED,
        ArbitrationStatus.REJECTED,
    )
    assert arbitration.decisions[1].reason is IntentionRejectionReason.CHANNEL_OCCUPIED
    assert arbitration.decisions[1].competing_intention_ids == (IntentionId(1),)
    assert arbitration.decisions[3].competing_intention_ids == (IntentionId(3),)
    assert arbitration.state.id_allocator.next_ids[int(IdKind.INTENTION)] == 5
    assert all(decision.candidate.origin.creation_tick == 9 for decision in arbitration.decisions)
    assert all(
        decision.candidate.origin.source_span.file_id == SourceFileId("policy.dtr")
        for decision in arbitration.decisions
    )


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
