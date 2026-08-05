"""Canonical per-entity action-channel arbitration for validated intentions."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.domain.ids import IntentionId
from kiwi.dsl.bytecode import InstructionIndex, InstructionSourceMapEntry
from kiwi.sim.intentions import (
    IntentionOrigin,
    MoveTowardIntention,
    TakeCoverIntention,
    ValidatedIntention,
    WaitIntention,
    required_capability_for,
)
from kiwi.sim.policies import PolicyBinding, PolicyBindings, PolicyValidationPhase
from kiwi.sim.state import MissionState


class ArbitrationStatus(StrEnum):
    """The deterministic disposition of one validated intention candidate."""

    SELECTED = "selected"
    REJECTED = "rejected"


class IntentionRejectionReason(StrEnum):
    """Stable reasons an otherwise valid intention loses arbitration."""

    CHANNEL_OCCUPIED = "channel_occupied"


@dataclass(frozen=True, slots=True)
class IntentionCandidate:
    """One validated payload plus its allocated causal origin."""

    origin: IntentionOrigin
    intention: ValidatedIntention

    def __post_init__(self) -> None:
        if not isinstance(self.origin, IntentionOrigin):
            raise ValueError("intention candidate requires an origin")
        if not isinstance(self.intention, (MoveTowardIntention, TakeCoverIntention, WaitIntention)):
            raise ValueError("intention candidate requires a validated intention")
        if self.intention.kind is not self.origin.kind:
            raise ValueError("intention candidate kind must match its origin")
        if self.intention.action_channel is not self.origin.action_channel:
            raise ValueError("intention candidate channel must match its origin")


@dataclass(frozen=True, slots=True)
class IntentionArbitration:
    """Selection or rejection of one candidate with explicit competitors."""

    candidate: IntentionCandidate
    status: ArbitrationStatus
    reason: IntentionRejectionReason | None = None
    competing_intention_ids: tuple[IntentionId, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.candidate, IntentionCandidate):
            raise ValueError("intention arbitration requires a candidate")
        if not isinstance(self.status, ArbitrationStatus):
            raise ValueError("intention arbitration requires a status")
        if not isinstance(self.competing_intention_ids, tuple):
            raise ValueError("arbitration competitors must be an immutable tuple")
        previous_id = 0
        for intention_id in self.competing_intention_ids:
            if not isinstance(intention_id, IntentionId):
                raise ValueError("arbitration competitors must be intention IDs")
            if intention_id.value <= previous_id:
                raise ValueError("arbitration competitors must be unique and ascending")
            previous_id = intention_id.value
        if self.status is ArbitrationStatus.SELECTED:
            if self.reason is not None or self.competing_intention_ids:
                raise ValueError("selected intentions cannot carry rejection data")
            return
        if self.reason is not IntentionRejectionReason.CHANNEL_OCCUPIED:
            raise ValueError("rejected intentions require a channel-occupied reason")
        if not self.competing_intention_ids:
            raise ValueError("rejected intentions require a competing intention")


@dataclass(frozen=True, slots=True)
class PolicyArbitrationPhase:
    """Successor allocation state and all candidates in canonical arbitration order."""

    state: MissionState
    decisions: tuple[IntentionArbitration, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("policy arbitration phase requires mission state")
        if not isinstance(self.decisions, tuple):
            raise ValueError("policy arbitration decisions must be an immutable tuple")
        previous_intention_id = 0
        previous_entity_id = 0
        previous_policy_order = -1
        for decision in self.decisions:
            if not isinstance(decision, IntentionArbitration):
                raise ValueError("policy arbitration decisions must be arbitrations")
            origin = decision.candidate.origin
            if origin.intention_id.value <= previous_intention_id:
                raise ValueError("policy arbitration intention IDs must be ascending")
            if origin.issuer_entity_id.value < previous_entity_id:
                raise ValueError("policy arbitration decisions must be entity-ID ordered")
            if origin.issuer_entity_id.value != previous_entity_id:
                previous_policy_order = -1
            if origin.policy_order <= previous_policy_order:
                raise ValueError("policy arbitration decisions must be policy-order ordered")
            previous_intention_id = origin.intention_id.value
            previous_entity_id = origin.issuer_entity_id.value
            previous_policy_order = origin.policy_order


def arbitrate_intentions(
    phase: PolicyValidationPhase,
    bindings: PolicyBindings,
) -> PolicyArbitrationPhase:
    """Select the first valid candidate in each entity action channel."""
    if not isinstance(phase, PolicyValidationPhase):
        raise TypeError("intention arbitration requires a policy validation phase")
    if not isinstance(bindings, PolicyBindings):
        raise TypeError("intention arbitration requires policy bindings")
    next_state = phase.state
    decisions: list[IntentionArbitration] = []
    for validation in phase.validations:
        if not validation.succeeded:
            continue
        binding = bindings.binding_for(validation.evaluation.entity_id)
        if binding is None:
            raise ValueError("intention arbitration requires a binding for every validation")
        selected: list[IntentionCandidate] = []
        for policy_order, intention in enumerate(validation.intentions):
            intention_id, id_allocator = next_state.id_allocator.allocate_intention()
            next_state = replace(next_state, id_allocator=id_allocator)
            source = _source_for_intention(binding, intention)
            candidate = IntentionCandidate(
                IntentionOrigin(
                    intention_id,
                    validation.evaluation.entity_id,
                    validation.evaluation.invocation_id,
                    source.expression_id,
                    source.span,
                    policy_order,
                    phase.state.tick,
                    intention.kind,
                ),
                intention,
            )
            competitors = tuple(
                selected_candidate.origin.intention_id
                for selected_candidate in selected
                if selected_candidate.origin.action_channel is candidate.origin.action_channel
            )
            if competitors:
                decisions.append(
                    IntentionArbitration(
                        candidate,
                        ArbitrationStatus.REJECTED,
                        IntentionRejectionReason.CHANNEL_OCCUPIED,
                        competitors,
                    )
                )
                continue
            selected.append(candidate)
            decisions.append(IntentionArbitration(candidate, ArbitrationStatus.SELECTED))
    return PolicyArbitrationPhase(next_state, tuple(decisions))


def _source_for_intention(
    binding: PolicyBinding,
    intention: ValidatedIntention,
) -> InstructionSourceMapEntry:
    capability = required_capability_for(intention)
    for entry in binding.artifact.capability_manifest.entries:
        if entry.function_id != binding.function_id:
            continue
        for requirement in entry.requirements:
            if requirement.capability != capability:
                continue
            for source in binding.artifact.bytecode.source_map.entries:
                if (
                    source.function_id == binding.function_id
                    and source.span == requirement.primary_span
                ):
                    return source
            break
    function = binding.artifact.bytecode.functions[binding.function_id.value]
    return binding.artifact.bytecode.source_map.entry_for(
        binding.function_id,
        InstructionIndex(len(function.instructions) - 1),
    )
