"""Canonical headless policy-VM invocation over immutable mission state."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.domain.ids import EntityId, PolicyInvocationId
from kiwi.dsl.compiler import CompiledArtifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.runtime_values import RecordValue
from kiwi.dsl.vm import DEFAULT_VM_BUDGETS, VMBudgets, VMRunResult, run_vm
from kiwi.sim.memory import EntityPolicyMemory
from kiwi.sim.observations import (
    RuntimeObservation,
    build_runtime_observations,
    observation_runtime_value,
)
from kiwi.sim.state import MissionState


@dataclass(frozen=True, slots=True)
class PolicyBinding:
    """One entity's compiled two-argument policy and initial memory value."""

    entity_id: EntityId
    artifact: CompiledArtifact
    function_id: FunctionId
    initial_memory: RecordValue
    budgets: VMBudgets = DEFAULT_VM_BUDGETS

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
        if not isinstance(self.initial_memory, RecordValue):
            raise ValueError("policy binding initial memory must be a record value")
        EntityPolicyMemory(self.entity_id, self.initial_memory)
        if not isinstance(self.budgets, VMBudgets):
            raise ValueError("policy binding requires VM budgets")


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


@dataclass(frozen=True, slots=True)
class PolicyEvaluation:
    """One raw VM result and its exact pre-evaluation inputs."""

    invocation_id: PolicyInvocationId
    entity_id: EntityId
    observation: RuntimeObservation
    input_memory: RecordValue
    result: VMRunResult

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
        binding = bindings.binding_for(entity.entity_id)
        if binding is None:
            continue
        stored_memory = state.policy_memory.memory_for(entity.entity_id)
        input_memory = binding.initial_memory if stored_memory is None else stored_memory
        invocation_id, id_allocator = next_state.id_allocator.allocate_policy_invocation()
        next_state = replace(next_state, id_allocator=id_allocator)
        evaluations.append(
            PolicyEvaluation(
                invocation_id,
                entity.entity_id,
                observation,
                input_memory,
                run_vm(
                    binding.artifact.bytecode,
                    binding.function_id,
                    (observation_runtime_value(observation), input_memory),
                    binding.budgets,
                ),
            )
        )
    return PolicyEvaluationPhase(next_state, tuple(evaluations))
