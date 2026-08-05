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
from kiwi.dsl.intrinsics import IntrinsicKind
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import IntegerValue, ListValue, RecordValue, StringValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.dsl.vm import VMBranchSelection, VMRunResult
from kiwi.sim.conditions import OperativeCondition, OperativeConditionStore
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactEstimate,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactStore,
)
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


def test_policy_invocation_expression_capture_does_not_change_authority_state() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    binding = PolicyBinding(
        entity.entity_id,
        _two_argument_policy_artifact(),
        FunctionId(0),
        MEMORY_SCHEMA,
        _memory("initial"),
    )

    untraced = invoke_policies(state, PolicyBindings((binding,)))
    traced = invoke_policies(state, PolicyBindings((binding,)), capture_expression_trace=True)

    assert traced.state == untraced.state
    assert traced.evaluations[0].invocation_id == untraced.evaluations[0].invocation_id
    assert traced.evaluations[0].result.value == untraced.evaluations[0].result.value
    assert untraced.evaluations[0].result.expression_traces == ()
    assert traced.evaluations[0].result.expression_traces


def test_policy_invocation_branch_capture_does_not_change_authority_state() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    binding = PolicyBinding(
        entity.entity_id,
        _branching_policy_artifact(),
        FunctionId(0),
        MEMORY_SCHEMA,
        _memory("initial"),
    )

    untraced = invoke_policies(state, PolicyBindings((binding,)))
    traced = invoke_policies(
        state,
        PolicyBindings((binding,)),
        capture_branch_selection_trace=True,
    )

    assert traced.state == untraced.state
    assert traced.evaluations[0].result.value == untraced.evaluations[0].result.value
    assert untraced.evaluations[0].result.branch_selection_traces == ()
    selections = tuple(
        trace.selection for trace in traced.evaluations[0].result.branch_selection_traces
    )
    assert selections == (VMBranchSelection.ELSE,)


def test_policy_invocation_standard_library_capture_does_not_change_authority_state() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    binding = PolicyBinding(
        entity.entity_id,
        _standard_library_policy_artifact(),
        FunctionId(0),
        MEMORY_SCHEMA,
        _memory("initial"),
    )

    untraced = invoke_policies(state, PolicyBindings((binding,)))
    traced = invoke_policies(
        state,
        PolicyBindings((binding,)),
        capture_standard_library_trace=True,
    )

    assert traced.state == untraced.state
    assert traced.evaluations[0].result.value == untraced.evaluations[0].result.value
    assert untraced.evaluations[0].result.standard_library_decision_traces == ()
    trace = traced.evaluations[0].result.standard_library_decision_traces[0]
    assert (trace.intrinsic, trace.input_count, trace.evaluated_count, trace.output_indices) == (
        IntrinsicKind.LIST_MIN_BY,
        2,
        2,
        (1,),
    )


def test_policy_invocation_captures_source_mapped_contact_field_reads_with_evidence() -> None:
    state, entity = add_entity(
        MissionState(tick=7), WorldPosition(WorldSubunits(1_000), WorldSubunits(2_000))
    )
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    contact_id, allocator = allocator.allocate_contact()
    state = replace(
        state,
        contacts=ContactStore(
            (
                ContactEstimate(
                    contact_id,
                    entity.entity_id,
                    WorldPosition(WorldSubunits(2_000), WorldSubunits(2_000)),
                    WorldSubunits(300),
                    ContactConfidence(7_500),
                    4,
                    ContactProvenance(
                        tuple(
                            ContactFieldProvenance(field, (evidence_event_id,))
                            for field in ContactField
                        )
                    ),
                ),
            ),
            lifecycle_tick=7,
        ),
        id_allocator=allocator,
    )
    binding = PolicyBinding(
        entity.entity_id,
        _contact_read_policy_artifact(),
        FunctionId(0),
        MEMORY_SCHEMA,
        _memory("initial"),
    )

    untraced = invoke_policies(state, PolicyBindings((binding,)))
    first = invoke_policies(
        state,
        PolicyBindings((binding,)),
        capture_observation_read_trace=True,
    )
    second = invoke_policies(
        state,
        PolicyBindings((binding,)),
        capture_observation_read_trace=True,
    )

    untraced_result = untraced.evaluations[0].result
    first_result = first.evaluations[0].result
    assert first.state == second.state == untraced.state
    assert first_result.value == second.evaluations[0].result.value == untraced_result.value
    assert untraced_result.observation_read_traces == ()
    assert (
        first_result.observation_read_traces == second.evaluations[0].result.observation_read_traces
    )
    assert tuple(trace.path for trace in first_result.observation_read_traces) == (
        ("nearest_contact",),
        ("nearest_contact", "confidence_basis_points"),
    )
    contact_read = first_result.observation_read_traces[1]
    assert contact_read.value == IntegerValue(7_500)
    assert contact_read.evidence_event_ids == (evidence_event_id,)
    assert contact_read.confidence_basis_points == 7_500
    assert contact_read.age_ticks == 3
    assert all(
        trace.source_map_entry in binding.artifact.bytecode.source_map.entries
        for trace in first_result.observation_read_traces
    )


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


def test_policy_invocation_skips_an_incapacitated_entity() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    state = replace(
        state,
        conditions=OperativeConditionStore((OperativeCondition(entity.entity_id, 0, 0),)),
    )
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                _two_argument_policy_artifact(),
                FunctionId(0),
                MEMORY_SCHEMA,
                _memory("initial"),
            ),
        )
    )

    phase = invoke_policies(state, bindings)

    assert phase.evaluations == ()
    assert phase.state.id_allocator == state.id_allocator


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


def test_policy_capability_preflight_blocks_declared_unavailable_wait() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                _decision_policy_artifact(),
                FunctionId(0),
                MEMORY_SCHEMA,
                _memory("initial"),
                available_capabilities=(),
            ),
        )
    )

    phase = invoke_policies(state, bindings)
    evaluation = phase.evaluations[0]
    validated = validate_policy_evaluations(phase, bindings)

    assert evaluation.capability_failure is not None
    assert evaluation.result.fault is not None
    assert evaluation.result.fault.message == "policy has an unavailable capability"
    assert validated.validations[0].failure is not None
    assert validated.validations[0].failure.code is PolicyValidationCode.CAPABILITY
    assert validated.validations[0].failure.primary_span is not None


def test_policy_capability_preflight_blocks_unavailable_cover_seek() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                _cover_seek_policy_artifact(),
                FunctionId(0),
                MEMORY_SCHEMA,
                _memory("initial"),
                available_capabilities=(),
            ),
        )
    )

    phase = invoke_policies(state, bindings)
    validated = validate_policy_evaluations(phase, bindings)

    assert phase.evaluations[0].capability_failure is not None
    assert phase.evaluations[0].result.fault is not None
    assert validated.validations[0].failure is not None
    assert validated.validations[0].failure.code is PolicyValidationCode.CAPABILITY
    assert validated.validations[0].failure.primary_span is not None


def test_policy_capability_validation_covers_wait_returned_by_a_helper() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    artifact = _indirect_wait_policy_artifact()
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                artifact,
                FunctionId(1),
                MEMORY_SCHEMA,
                _memory("initial"),
                available_capabilities=(),
            ),
        )
    )

    phase = invoke_policies(state, bindings)
    validated = validate_policy_evaluations(phase, bindings)

    assert artifact.capability_manifest.entries[0].requirements == ()
    assert phase.evaluations[0].capability_failure is None
    assert phase.evaluations[0].result.succeeded
    assert validated.validations[0].failure is not None
    assert validated.validations[0].failure.code is PolicyValidationCode.CAPABILITY
    assert validated.validations[0].failure.primary_span is None


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


def _branching_policy_artifact() -> CompiledArtifact:
    return _artifact(
        "type SelfObservation = { incapacitated: Bool }\n"
        "type Observation = { self: SelfObservation }\n"
        "type Memory = { label: String }\n"
        "policy decide(observation: Observation, memory: Memory) -> Memory = "
        "if observation.self.incapacitated then memory else memory\n"
    )


def _standard_library_policy_artifact() -> CompiledArtifact:
    return _artifact(
        "type Observation = { tick: Int }\n"
        "type Memory = { label: String }\n"
        "policy decide(observation: Observation, memory: Memory) -> Memory = "
        "let selected = List.min_by([2, 1], fn item -> item) in memory\n"
    )


def _contact_read_policy_artifact() -> CompiledArtifact:
    return _artifact(
        "type Contact = { age_ticks: Int, confidence_basis_points: Int, contact_id: Int, "
        "estimated_position: Position, uncertainty_radius: Distance }\n"
        "type Observation = { nearest_contact: Option<Contact> }\n"
        "type Memory = { label: String }\n"
        "policy decide(observation: Observation, memory: Memory) -> Memory = "
        "match observation.nearest_contact with\n"
        "| Some(contact) -> let confidence = contact.confidence_basis_points in memory\n"
        "| None -> memory\n"
    )


def _indirect_wait_policy_artifact() -> CompiledArtifact:
    return _artifact(
        "type SelfObservation = { entity_id: Int, position: Position }\n"
        "type Observation = { self: SelfObservation, tick: Int }\n"
        "type Memory = { label: String }\n"
        "type Wait = { duration: Duration }\n"
        "type Decision = { intentions: List<Wait>, memory: Memory }\n"
        "fn wait() -> Wait = Wait { duration = 1s }\n"
        "policy decide(observation: Observation, memory: Memory) -> Decision = "
        "Decision { intentions = [wait()], memory = memory }\n"
    )


def _artifact(text: str) -> CompiledArtifact:
    source = SourceFile(SourceFileId("policy.dtr"), text)
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))


def _cover_seek_policy_artifact() -> CompiledArtifact:
    return _artifact(
        "type SelfObservation = { entity_id: Int, position: Position }\n"
        "type Observation = { self: SelfObservation, tick: Int }\n"
        "type Memory = { label: String }\n"
        "type TakeCover = { cover_id: Int, side: String }\n"
        "type Decision = { intentions: List<TakeCover>, memory: Memory }\n"
        "policy decide(observation: Observation, memory: Memory) -> Decision = "
        'Decision { intentions = [Cover.seek(1, "left")], memory = memory }\n'
    )
