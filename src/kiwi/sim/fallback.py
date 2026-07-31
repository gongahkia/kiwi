"""Deterministic hold decisions for policy validation failures."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.dsl.runtime_values import RecordValue
from kiwi.sim.intentions import ValidatedIntention
from kiwi.sim.policies import PolicyValidation, PolicyValidationPhase
from kiwi.sim.state import MissionState


class PolicyFallbackKind(StrEnum):
    """The closed initial fallback behaviour after a failed policy result."""

    HOLD = "hold"


@dataclass(frozen=True, slots=True)
class ResolvedPolicyDecision:
    """One successful policy decision or deterministic hold fallback."""

    validation: PolicyValidation
    memory: RecordValue
    intentions: tuple[ValidatedIntention, ...]
    fallback_kind: PolicyFallbackKind | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.validation, PolicyValidation):
            raise ValueError("resolved policy decision requires a policy validation")
        if not isinstance(self.memory, RecordValue):
            raise ValueError("resolved policy decision requires record memory")
        if not isinstance(self.intentions, tuple):
            raise ValueError("resolved policy intentions must be an immutable tuple")
        if self.validation.succeeded:
            if self.fallback_kind is not None:
                raise ValueError("successful policy decisions cannot use fallback")
            if (
                self.memory != self.validation.memory
                or self.intentions != self.validation.intentions
            ):
                raise ValueError("successful policy decisions must retain validated output")
            return
        if self.fallback_kind is not PolicyFallbackKind.HOLD:
            raise ValueError("failed policy decisions must use the hold fallback")
        if self.memory != self.validation.evaluation.input_memory:
            raise ValueError("hold fallback must preserve input memory")
        if self.intentions:
            raise ValueError("hold fallback cannot emit intentions")

    @property
    def fallback_used(self) -> bool:
        """Return whether this decision replaced a failed policy result."""
        return self.fallback_kind is not None


@dataclass(frozen=True, slots=True)
class PolicyDecisionPhase:
    """A policy pass with every validation resolved to a safe decision."""

    state: MissionState
    decisions: tuple[ResolvedPolicyDecision, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("policy decision phase requires mission state")
        if not isinstance(self.decisions, tuple):
            raise ValueError("policy decisions must be an immutable tuple")
        previous_entity_id = 0
        for decision in self.decisions:
            if not isinstance(decision, ResolvedPolicyDecision):
                raise ValueError("policy decisions must be resolved policy decisions")
            entity_id = decision.validation.evaluation.entity_id.value
            if entity_id <= previous_entity_id:
                raise ValueError("policy decisions must be entity-ID ordered")
            previous_entity_id = entity_id


def resolve_policy_decisions(phase: PolicyValidationPhase) -> PolicyDecisionPhase:
    """Replace each failed policy result with its explicit deterministic hold."""
    if not isinstance(phase, PolicyValidationPhase):
        raise TypeError("policy fallback requires a policy validation phase")
    decisions: list[ResolvedPolicyDecision] = []
    for validation in phase.validations:
        if validation.succeeded:
            if validation.memory is None:
                raise AssertionError("successful policy validation has no memory")
            decisions.append(
                ResolvedPolicyDecision(validation, validation.memory, validation.intentions)
            )
            continue
        decisions.append(
            ResolvedPolicyDecision(
                validation,
                validation.evaluation.input_memory,
                (),
                PolicyFallbackKind.HOLD,
            )
        )
    return PolicyDecisionPhase(phase.state, tuple(decisions))
