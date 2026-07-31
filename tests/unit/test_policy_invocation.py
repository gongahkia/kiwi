from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EntityId, IdKind, PolicyInvocationId
from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import IntegerValue, ListValue, RecordValue, StringValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.dsl.vm import VMRunResult
from kiwi.sim.intentions import WaitIntention
from kiwi.sim.memory import PolicyMemoryStore
from kiwi.sim.policies import (
    PolicyBinding,
    PolicyBindings,
    PolicyEvaluationPhase,
    PolicyValidationCode,
    invoke_policies,
    validate_policy_evaluations,
)
from kiwi.sim.state import MissionState, add_entity

MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_policy_invocation_uses_pre_state_memory_and_canonical_entity_order() -> None:
    first_state, first = add_entity(
        MissionState(tick=6), WorldPosition(WorldSubunits(1), WorldSubunits(2))
    )
    state, second = add_entity(first_state, WorldPosition(WorldSubunits(3), WorldSubunits(4)))
    initial_memory = _memory("initial")
    persisted_memory = _memory("persisted")
    state = replace(
        state,
        policy_memory=PolicyMemoryStore().with_memory(second.entity_id, persisted_memory),
    )
    artifact = _two_argument_policy_artifact()
    bindings = PolicyBindings(
        (
            PolicyBinding(first.entity_id, artifact, FunctionId(0), MEMORY_SCHEMA, initial_memory),
            PolicyBinding(second.entity_id, artifact, FunctionId(0), MEMORY_SCHEMA, initial_memory),
        )
    )

    phase = invoke_policies(state, bindings)

    assert isinstance(phase, PolicyEvaluationPhase)
    assert tuple(evaluation.entity_id for evaluation in phase.evaluations) == (
        first.entity_id,
        second.entity_id,
    )
    assert tuple(evaluation.invocation_id for evaluation in phase.evaluations) == (
        PolicyInvocationId(1),
        PolicyInvocationId(2),
    )
    assert tuple(evaluation.observation.tick for evaluation in phase.evaluations) == (6, 6)
    assert tuple(evaluation.input_memory for evaluation in phase.evaluations) == (
        initial_memory,
        persisted_memory,
    )
    assert all(evaluation.result.succeeded for evaluation in phase.evaluations)
    assert tuple(evaluation.result.value for evaluation in phase.evaluations) == (
        initial_memory,
        persisted_memory,
    )
    assert state.id_allocator.next_ids[int(IdKind.POLICY_INVOCATION)] == 1
    assert phase.state.id_allocator.next_ids[int(IdKind.POLICY_INVOCATION)] == 3


def test_policy_bindings_reject_noncanonical_and_unbound_entries() -> None:
    artifact = _two_argument_policy_artifact()
    binding = PolicyBinding(EntityId(1), artifact, FunctionId(0), MEMORY_SCHEMA, _memory("initial"))

    with pytest.raises(ValueError, match="entity-ID ordered"):
        PolicyBindings(
            (
                PolicyBinding(EntityId(2), artifact, FunctionId(0), MEMORY_SCHEMA, _memory("two")),
                binding,
            )
        )
    with pytest.raises(ValueError, match="belong to mission entities"):
        invoke_policies(MissionState(), PolicyBindings((binding,)))


def test_policy_binding_requires_a_two_argument_policy_entry_point() -> None:
    artifact = _one_argument_policy_artifact()

    with pytest.raises(ValueError, match="observation and memory"):
        PolicyBinding(EntityId(1), artifact, FunctionId(0), MEMORY_SCHEMA, _memory("initial"))

    with pytest.raises(ValueError, match="policy entry point"):
        PolicyBinding(
            EntityId(1),
            _helper_and_policy_artifact(),
            FunctionId(0),
            MEMORY_SCHEMA,
            _memory("initial"),
        )


def test_policy_validation_accepts_wait_and_reports_malformed_decisions() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                _decision_policy_artifact(),
                FunctionId(0),
                MEMORY_SCHEMA,
                _memory("initial"),
            ),
        )
    )
    phase = invoke_policies(state, bindings)

    validated = validate_policy_evaluations(phase, bindings)

    assert validated.validations[0].succeeded
    assert validated.validations[0].memory == _memory("initial")
    assert validated.validations[0].intentions == (
        WaitIntention(Quantity(QuantityDimension.DURATION, ExactRational(1, 1))),
    )

    malformed_decision = RecordValue(
        "Decision",
        ("intentions", "memory"),
        (ListValue(()), IntegerValue(1)),
    )
    malformed_phase = replace(
        phase,
        evaluations=(replace(phase.evaluations[0], result=VMRunResult(malformed_decision)),),
    )
    malformed = validate_policy_evaluations(malformed_phase, bindings)

    assert not malformed.validations[0].succeeded
    assert malformed.validations[0].failure is not None
    assert malformed.validations[0].failure.code is PolicyValidationCode.RESULT
    assert malformed.validations[0].failure.path == ("memory",)


def _memory(label: str) -> RecordValue:
    return RecordValue("Memory", ("label",), (StringValue(label),))


def _two_argument_policy_artifact() -> CompiledArtifact:
    return _artifact(
        "type SelfObservation = { entity_id: Int, position: Position }\n"
        "type Observation = { self: SelfObservation, tick: Int }\n"
        "type Memory = { label: String }\n"
        "policy decide(observation: Observation, memory: Memory) -> Memory = memory\n"
    )


def _one_argument_policy_artifact() -> CompiledArtifact:
    return _artifact(
        "type Memory = { label: String }\npolicy decide(memory: Memory) -> Memory = memory\n"
    )


def _helper_and_policy_artifact() -> CompiledArtifact:
    return _artifact(
        "type Memory = { label: String }\n"
        "fn helper(memory: Memory) -> Memory = memory\n"
        "policy decide(observation: Memory, memory: Memory) -> Memory = memory\n"
    )


def _decision_policy_artifact() -> CompiledArtifact:
    return _artifact(
        "type SelfObservation = { entity_id: Int, position: Position }\n"
        "type Observation = { self: SelfObservation, tick: Int }\n"
        "type Memory = { label: String }\n"
        "type Wait = { duration: Duration }\n"
        "type Decision = { intentions: List<Wait>, memory: Memory }\n"
        "policy decide(observation: Observation, memory: Memory) -> Decision = "
        "Decision { intentions = [Wait { duration = 1s }], memory = memory }\n"
    )


def _artifact(text: str) -> CompiledArtifact:
    source = SourceFile(SourceFileId("policy.dtr"), text)
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
