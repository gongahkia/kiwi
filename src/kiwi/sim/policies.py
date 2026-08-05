"""Canonical headless policy-VM invocation over immutable mission state."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.domain.ids import EntityId, PolicyInvocationId
from kiwi.dsl.capabilities import (
    AIM_CAPABILITY,
    FIRE_CAPABILITY,
    MOVE_TOWARD_CAPABILITY,
    TAKE_COVER_CAPABILITY,
    WAIT_CAPABILITY,
    CapabilityId,
)
from kiwi.dsl.compiler import CompiledArtifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.policy_result import (
    MemorySchema,
    PolicyResultValidationFailure,
    validate_memory,
    validate_policy_result,
)
from kiwi.dsl.runtime_values import RecordValue
from kiwi.dsl.source import SourceSpan
from kiwi.dsl.vm import DEFAULT_VM_BUDGETS, VMBudgets, VMFault, VMFaultCode, VMRunResult, run_vm
from kiwi.sim.intentions import (
    AimIntention,
    FireIntention,
    IntentionValidationFailure,
    MoveTowardIntention,
    TakeCoverIntention,
    ValidatedIntention,
    WaitIntention,
    required_capability_for,
    validate_runtime_intention,
)
from kiwi.sim.memory import EntityPolicyMemory
from kiwi.sim.observations import (
    RuntimeObservation,
    build_runtime_observations,
    observation_runtime_value,
)
from kiwi.sim.policy_versions import PolicyVersion
from kiwi.sim.state import MissionState


@dataclass(frozen=True, slots=True)
class PolicyBinding:
    """One entity's compiled two-argument policy and initial memory value."""

    entity_id: EntityId
    artifact: CompiledArtifact
    function_id: FunctionId
    memory_schema: MemorySchema
    initial_memory: RecordValue
    budgets: VMBudgets = DEFAULT_VM_BUDGETS
    available_capabilities: tuple[CapabilityId, ...] = (
        AIM_CAPABILITY,
        FIRE_CAPABILITY,
        MOVE_TOWARD_CAPABILITY,
        TAKE_COVER_CAPABILITY,
        WAIT_CAPABILITY,
    )

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("policy binding requires an entity ID")
        if not isinstance(self.artifact, CompiledArtifact):
            raise ValueError("policy binding requires a compiled artifact")
        if not isinstance(self.function_id, FunctionId):
            raise ValueError("policy binding requires a function ID")
        if self.function_id.value >= len(self.artifact.bytecode.functions):
            raise ValueError("policy binding function is outside the bytecode module")
        if not any(
            entry.function_id == self.function_id
            for entry in self.artifact.capability_manifest.entries
        ):
            raise ValueError("policy binding function must be a policy entry point")
        if self.artifact.bytecode.functions[self.function_id.value].arity != 2:
            raise ValueError("policy binding entry point must accept observation and memory")
        if not isinstance(self.memory_schema, MemorySchema):
            raise ValueError("policy binding requires a memory schema")
        if not isinstance(self.initial_memory, RecordValue):
            raise ValueError("policy binding initial memory must be a record value")
        EntityPolicyMemory(self.entity_id, self.initial_memory)
        if isinstance(
            validate_memory(self.initial_memory, self.memory_schema), PolicyResultValidationFailure
        ):
            raise ValueError("policy binding initial memory does not match its schema")
        if not isinstance(self.budgets, VMBudgets):
            raise ValueError("policy binding requires VM budgets")
        if not isinstance(self.available_capabilities, tuple):
            raise ValueError("policy binding capabilities must be an immutable tuple")
        if any(
            not isinstance(capability, CapabilityId) for capability in self.available_capabilities
        ):
            raise ValueError("policy binding capabilities must contain capability IDs")
        capability_ids = tuple(capability.value for capability in self.available_capabilities)
        if capability_ids != tuple(sorted(capability_ids)) or len(set(capability_ids)) != len(
            capability_ids
        ):
            raise ValueError("policy binding capabilities must be unique and lexically ordered")

    @property
    def policy_version(self) -> PolicyVersion:
        """Return the canonical identity of this deployed policy entry point."""
        return PolicyVersion.from_artifact(self.artifact, self.function_id)


@dataclass(frozen=True, slots=True)
class PolicyBindings:
    """An immutable entity-ID-ordered set of applicable policy bindings."""

    entries: tuple[PolicyBinding, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.entries, tuple):
            raise ValueError("policy bindings must be an immutable tuple")
        previous_id = 0
        for entry in self.entries:
            if not isinstance(entry, PolicyBinding):
                raise ValueError("policy bindings must contain policy bindings")
            if entry.entity_id.value <= previous_id:
                raise ValueError("policy bindings must be unique and entity-ID ordered")
            previous_id = entry.entity_id.value

    def binding_for(self, entity_id: EntityId) -> PolicyBinding | None:
        """Return the matching binding without relying on mapping iteration order."""
        if not isinstance(entity_id, EntityId):
            raise ValueError("policy binding lookup requires an entity ID")
        for entry in self.entries:
            if entry.entity_id == entity_id:
                return entry
        return None


EMPTY_POLICY_BINDINGS = PolicyBindings()


@dataclass(frozen=True, slots=True)
class PolicyEvaluation:
    """One raw VM result and its exact pre-evaluation inputs."""

    invocation_id: PolicyInvocationId
    entity_id: EntityId
    observation: RuntimeObservation
    input_memory: RecordValue
    result: VMRunResult
    capability_failure: PolicyCapabilityFailure | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.invocation_id, PolicyInvocationId):
            raise ValueError("policy evaluation requires a policy invocation ID")
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("policy evaluation requires an entity ID")
        if not isinstance(self.observation, RuntimeObservation):
            raise ValueError("policy evaluation requires a runtime observation")
        if self.observation.self_observation.entity_id != self.entity_id:
            raise ValueError("policy evaluation observation must belong to its entity")
        if not isinstance(self.input_memory, RecordValue):
            raise ValueError("policy evaluation requires record memory")
        if not isinstance(self.result, VMRunResult):
            raise ValueError("policy evaluation requires a VM result")
        if self.capability_failure is not None and not isinstance(
            self.capability_failure, PolicyCapabilityFailure
        ):
            raise ValueError("policy evaluation capability failure must be structured")


@dataclass(frozen=True, slots=True)
class PolicyEvaluationPhase:
    """The successor allocation state and entity-ID-ordered VM evaluations."""

    state: MissionState
    evaluations: tuple[PolicyEvaluation, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("policy evaluation phase requires mission state")
        if not isinstance(self.evaluations, tuple):
            raise ValueError("policy evaluations must be an immutable tuple")
        previous_entity_id = 0
        previous_invocation_id = 0
        for evaluation in self.evaluations:
            if not isinstance(evaluation, PolicyEvaluation):
                raise ValueError("policy evaluations must contain policy evaluations")
            if evaluation.entity_id.value <= previous_entity_id:
                raise ValueError("policy evaluations must be entity-ID ordered")
            if evaluation.invocation_id.value <= previous_invocation_id:
                raise ValueError("policy invocation IDs must be ascending")
            previous_entity_id = evaluation.entity_id.value
            previous_invocation_id = evaluation.invocation_id.value


class PolicyValidationCode(StrEnum):
    """Stable per-policy result validation outcomes before fallback handling."""

    VM_FAULT = "P001_VM_FAULT"
    RESULT = "P002_RESULT"
    INTENTION = "P003_INTENTION"
    CAPABILITY = "P004_CAPABILITY"


@dataclass(frozen=True, slots=True)
class PolicyCapabilityFailure:
    """One unavailable source-linked capability before or after VM execution."""

    capability: CapabilityId
    primary_span: SourceSpan | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.capability, CapabilityId):
            raise ValueError("policy capability failure requires a capability ID")
        if self.primary_span is not None and not isinstance(self.primary_span, SourceSpan):
            raise ValueError("policy capability failure primary span must be a source span")


@dataclass(frozen=True, slots=True)
class PolicyValidationFailure:
    """One structured boundary failure retained for deterministic fallback."""

    code: PolicyValidationCode
    message: str
    path: tuple[str, ...] = ()
    primary_span: SourceSpan | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.code, PolicyValidationCode):
            raise ValueError("policy validation failure requires a validation code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("policy validation failure requires a message")
        if not isinstance(self.path, tuple) or any(
            not isinstance(part, str) or not part for part in self.path
        ):
            raise ValueError("policy validation failure path must be non-empty strings")
        if self.primary_span is not None and not isinstance(self.primary_span, SourceSpan):
            raise ValueError("policy validation failure primary span must be a source span")


@dataclass(frozen=True, slots=True)
class PolicyValidation:
    """One validated decision or a structured failure with no fallback applied."""

    evaluation: PolicyEvaluation
    memory: RecordValue | None = None
    intentions: tuple[ValidatedIntention, ...] = ()
    failure: PolicyValidationFailure | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.evaluation, PolicyEvaluation):
            raise ValueError("policy validation requires a policy evaluation")
        if not isinstance(self.intentions, tuple):
            raise ValueError("policy validation intentions must be an immutable tuple")
        if any(
            not isinstance(
                intention,
                (AimIntention, FireIntention, MoveTowardIntention, TakeCoverIntention, WaitIntention),
            )
            for intention in self.intentions
        ):
            raise ValueError("policy validation intentions must be validated intentions")
        if self.failure is None:
            if not isinstance(self.memory, RecordValue):
                raise ValueError("successful policy validation requires record memory")
            return
        if not isinstance(self.failure, PolicyValidationFailure):
            raise ValueError("policy validation failure must be structured")
        if self.memory is not None or self.intentions:
            raise ValueError("failed policy validation cannot contain a decision")

    @property
    def succeeded(self) -> bool:
        """Return whether the policy produced a fully validated decision."""
        return self.failure is None


@dataclass(frozen=True, slots=True)
class PolicyValidationPhase:
    """Raw-evaluation successor state plus entity-ID-ordered validation results."""

    state: MissionState
    validations: tuple[PolicyValidation, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("policy validation phase requires mission state")
        if not isinstance(self.validations, tuple):
            raise ValueError("policy validations must be an immutable tuple")
        previous_entity_id = 0
        for validation in self.validations:
            if not isinstance(validation, PolicyValidation):
                raise ValueError("policy validations must contain policy validations")
            if validation.evaluation.entity_id.value <= previous_entity_id:
                raise ValueError("policy validations must be entity-ID ordered")
            previous_entity_id = validation.evaluation.entity_id.value


def invoke_policies(state: MissionState, bindings: PolicyBindings) -> PolicyEvaluationPhase:
    """Invoke applicable policy entries in canonical entity-ID order without state mutation."""
    if not isinstance(state, MissionState):
        raise TypeError("policy invocation requires mission state")
    if not isinstance(bindings, PolicyBindings):
        raise TypeError("policy invocation requires policy bindings")
    entity_ids = tuple(entity.entity_id for entity in state.entities)
    if any(binding.entity_id not in entity_ids for binding in bindings.entries):
        raise ValueError("policy bindings must belong to mission entities")

    next_state = state
    evaluations: list[PolicyEvaluation] = []
    observations = build_runtime_observations(state)
    for entity, observation in zip(state.entities, observations, strict=True):
        if state.conditions.is_incapacitated(entity.entity_id):
            continue
        binding = bindings.binding_for(entity.entity_id)
        if binding is None:
            continue
        stored_memory = state.policy_memory.memory_for(entity.entity_id)
        input_memory = binding.initial_memory if stored_memory is None else stored_memory
        invocation_id, id_allocator = next_state.id_allocator.allocate_policy_invocation()
        next_state = replace(next_state, id_allocator=id_allocator)
        capability_failure = _first_unavailable_declared_capability(binding)
        result = (
            VMRunResult(
                None,
                VMFault(
                    VMFaultCode.ENTRY,
                    "policy has an unavailable capability",
                    binding.function_id,
                ),
            )
            if capability_failure is not None
            else run_vm(
                binding.artifact.bytecode,
                binding.function_id,
                (observation_runtime_value(observation), input_memory),
                binding.budgets,
            )
        )
        evaluations.append(
            PolicyEvaluation(
                invocation_id,
                entity.entity_id,
                observation,
                input_memory,
                result,
                capability_failure,
            )
        )
    return PolicyEvaluationPhase(next_state, tuple(evaluations))


def validate_policy_evaluations(
    phase: PolicyEvaluationPhase,
    bindings: PolicyBindings,
) -> PolicyValidationPhase:
    """Validate raw VM results in canonical order without applying fallback or state updates."""
    if not isinstance(phase, PolicyEvaluationPhase):
        raise TypeError("policy validation requires an evaluation phase")
    if not isinstance(bindings, PolicyBindings):
        raise TypeError("policy validation requires policy bindings")
    validations: list[PolicyValidation] = []
    for evaluation in phase.evaluations:
        binding = bindings.binding_for(evaluation.entity_id)
        if binding is None:
            raise ValueError("policy validation requires a binding for every evaluation")
        validations.append(_validate_policy_evaluation(evaluation, binding))
    return PolicyValidationPhase(phase.state, tuple(validations))


def _validate_policy_evaluation(
    evaluation: PolicyEvaluation,
    binding: PolicyBinding,
) -> PolicyValidation:
    if evaluation.capability_failure is not None:
        failure = evaluation.capability_failure
        return PolicyValidation(
            evaluation,
            failure=PolicyValidationFailure(
                PolicyValidationCode.CAPABILITY,
                f"policy capability is unavailable: {failure.capability.value}",
                primary_span=failure.primary_span,
            ),
        )
    if evaluation.result.fault is not None:
        return PolicyValidation(
            evaluation,
            failure=PolicyValidationFailure(
                PolicyValidationCode.VM_FAULT,
                f"policy VM fault: {evaluation.result.fault.code.value}",
            ),
        )
    if evaluation.result.value is None:
        return PolicyValidation(
            evaluation,
            failure=PolicyValidationFailure(
                PolicyValidationCode.VM_FAULT,
                f"policy VM fault: {VMFaultCode.ENTRY.value}",
            ),
        )
    result = validate_policy_result(evaluation.result.value, binding.memory_schema)
    if isinstance(result, PolicyResultValidationFailure):
        return PolicyValidation(
            evaluation,
            failure=PolicyValidationFailure(
                PolicyValidationCode.RESULT,
                f"policy result validation failed: {result.code.value}",
                result.path,
            ),
        )
    intentions: list[ValidatedIntention] = []
    for index, value in enumerate(result.intentions):
        intention = validate_runtime_intention(value)
        if isinstance(intention, IntentionValidationFailure):
            return PolicyValidation(
                evaluation,
                failure=PolicyValidationFailure(
                    PolicyValidationCode.INTENTION,
                    f"policy intention validation failed: {intention.code.value}",
                    ("intentions", str(index)) + intention.path,
                ),
            )
        capability = required_capability_for(intention)
        if capability not in binding.available_capabilities:
            return PolicyValidation(
                evaluation,
                failure=PolicyValidationFailure(
                    PolicyValidationCode.CAPABILITY,
                    f"policy capability is unavailable: {capability.value}",
                    primary_span=_declared_capability_span(binding, capability),
                ),
            )
        intentions.append(intention)
    return PolicyValidation(evaluation, result.memory, tuple(intentions))


def _first_unavailable_declared_capability(
    binding: PolicyBinding,
) -> PolicyCapabilityFailure | None:
    for entry in binding.artifact.capability_manifest.entries:
        if entry.function_id != binding.function_id:
            continue
        for requirement in entry.requirements:
            if requirement.capability not in binding.available_capabilities:
                return PolicyCapabilityFailure(requirement.capability, requirement.primary_span)
        return None
    raise AssertionError("policy binding entry point is absent from its capability manifest")


def _declared_capability_span(
    binding: PolicyBinding,
    capability: CapabilityId,
) -> SourceSpan | None:
    for entry in binding.artifact.capability_manifest.entries:
        if entry.function_id != binding.function_id:
            continue
        for requirement in entry.requirements:
            if requirement.capability == capability:
                return requirement.primary_span
        return None
    raise AssertionError("policy binding entry point is absent from its capability manifest")
