from __future__ import annotations

from dataclasses import replace

from kiwi.domain.geometry import WorldPosition, WorldSubunits
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
from kiwi.dsl.runtime_values import ListValue, QuantityValue, RecordValue, StringValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.dsl.vm import VMBudgets, VMRunResult
from kiwi.sim.fallback import PolicyFallbackKind, resolve_policy_decisions
from kiwi.sim.policies import (
    PolicyBinding,
    PolicyBindings,
    PolicyValidationCode,
    invoke_policies,
    validate_policy_evaluations,
)
from kiwi.sim.state import MissionState, add_entity

MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_vm_fault_resolves_to_hold_with_unchanged_memory() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    input_memory = _memory("initial")
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                _decision_policy_artifact(),
                FunctionId(0),
                MEMORY_SCHEMA,
                input_memory,
                budgets=VMBudgets(instruction_limit=0),
            ),
        )
    )
    validations = validate_policy_evaluations(invoke_policies(state, bindings), bindings)

    phase = resolve_policy_decisions(validations)

    decision = phase.decisions[0]
    assert decision.fallback_used
    assert decision.fallback_kind is PolicyFallbackKind.HOLD
    assert decision.memory == input_memory
    assert decision.intentions == ()
    assert decision.validation.failure is not None
    assert decision.validation.failure.code is PolicyValidationCode.VM_FAULT
    assert phase.state is validations.state


def test_invalid_intention_resolves_to_the_same_hold_fallback() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    input_memory = _memory("initial")
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                _decision_policy_artifact(),
                FunctionId(0),
                MEMORY_SCHEMA,
                input_memory,
            ),
        )
    )
    evaluations = invoke_policies(state, bindings)
    invalid_wait = RecordValue(
        "Wait",
        ("duration",),
        (QuantityValue(Quantity(QuantityDimension.DURATION, ExactRational(-1, 1))),),
    )
    invalid_result = RecordValue(
        "Decision",
        ("intentions", "memory"),
        (ListValue((invalid_wait,)), input_memory),
    )
    invalid_evaluations = replace(
        evaluations,
        evaluations=(replace(evaluations.evaluations[0], result=VMRunResult(invalid_result)),),
    )
    validations = validate_policy_evaluations(invalid_evaluations, bindings)

    phase = resolve_policy_decisions(validations)

    decision = phase.decisions[0]
    assert decision.fallback_used
    assert decision.fallback_kind is PolicyFallbackKind.HOLD
    assert decision.memory == input_memory
    assert decision.intentions == ()
    assert decision.validation.failure is not None
    assert decision.validation.failure.code is PolicyValidationCode.INTENTION


def test_invalid_memory_resolves_to_the_same_hold_fallback() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    input_memory = _memory("initial")
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                _decision_policy_artifact(),
                FunctionId(0),
                MEMORY_SCHEMA,
                input_memory,
            ),
        )
    )
    evaluations = invoke_policies(state, bindings)
    invalid_result = RecordValue(
        "Decision",
        ("intentions", "memory"),
        (ListValue(()), StringValue("not-memory")),
    )
    invalid_evaluations = replace(
        evaluations,
        evaluations=(replace(evaluations.evaluations[0], result=VMRunResult(invalid_result)),),
    )
    validations = validate_policy_evaluations(invalid_evaluations, bindings)

    phase = resolve_policy_decisions(validations)

    decision = phase.decisions[0]
    assert decision.fallback_used
    assert decision.fallback_kind is PolicyFallbackKind.HOLD
    assert decision.memory == input_memory
    assert decision.intentions == ()
    assert decision.validation.failure is not None
    assert decision.validation.failure.code is PolicyValidationCode.RESULT


def _memory(label: str) -> RecordValue:
    return RecordValue("Memory", ("label",), (StringValue(label),))


def _decision_policy_artifact() -> CompiledArtifact:
    source = SourceFile(
        SourceFileId("policy.dtr"),
        "type SelfObservation = { entity_id: Int, position: Position }\n"
        "type Observation = { self: SelfObservation, tick: Int }\n"
        "type Memory = { label: String }\n"
        "type Wait = { duration: Duration }\n"
        "type Decision = { intentions: List<Wait>, memory: Memory }\n"
        "policy decide(observation: Observation, memory: Memory) -> Decision = "
        "Decision { intentions = [Wait { duration = 1s }], memory = memory }\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
