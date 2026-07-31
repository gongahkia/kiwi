"""Canonical policy lifecycle event emission after validation and arbitration."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.domain.ids import EventId, PolicyInvocationId
from kiwi.sim.arbitration import ArbitrationStatus, IntentionArbitration, PolicyArbitrationPhase
from kiwi.sim.events import (
    CanonicalEvent,
    EventHeader,
    IntentionEmitted,
    IntentionRejected,
    IntentionSelected,
    PolicyEvaluated,
    canonical_event_order,
)
from kiwi.sim.policies import PolicyValidation, PolicyValidationPhase
from kiwi.sim.state import MissionState


@dataclass(frozen=True, slots=True)
class PolicyEventPhase:
    """Successor allocation state and the canonical events of one policy pass."""

    state: MissionState
    events: tuple[CanonicalEvent, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("policy event phase requires mission state")
        if not isinstance(self.events, tuple):
            raise ValueError("policy event phase events must be an immutable tuple")
        if canonical_event_order(self.events) != self.events:
            raise ValueError("policy event phase events must be canonically ordered")


def emit_policy_events(
    validation_phase: PolicyValidationPhase,
    arbitration_phase: PolicyArbitrationPhase,
) -> PolicyEventPhase:
    """Emit policy, candidate, and resolution events in canonical phase order."""
    if not isinstance(validation_phase, PolicyValidationPhase):
        raise TypeError("policy events require a policy validation phase")
    if not isinstance(arbitration_phase, PolicyArbitrationPhase):
        raise TypeError("policy events require a policy arbitration phase")
    if validation_phase.state.tick != arbitration_phase.state.tick:
        raise ValueError("policy event phases must share a mission tick")

    next_state = arbitration_phase.state
    events: list[CanonicalEvent] = []
    policy_event_ids: list[tuple[PolicyInvocationId, EventId]] = []
    for validation in validation_phase.validations:
        next_state, header = _allocate_event_header(next_state)
        events.append(PolicyEvaluated(header, validation))
        policy_event_ids.append((validation.evaluation.invocation_id, header.event_id))

    for decision in arbitration_phase.decisions:
        validation = _validation_for_candidate(
            validation_phase, decision.candidate.origin.invocation_id
        )
        policy_event_id = _policy_event_id_for_invocation(
            policy_event_ids,
            decision.candidate.origin.invocation_id,
        )
        _require_candidate_matches_validation(validation, decision)
        next_state, emitted_header = _allocate_event_header(next_state, (policy_event_id,))
        events.append(IntentionEmitted(emitted_header, decision.candidate))
        next_state, resolution_header = _allocate_event_header(
            next_state,
            (emitted_header.event_id,),
        )
        if decision.status is ArbitrationStatus.SELECTED:
            events.append(IntentionSelected(resolution_header, decision))
        else:
            events.append(IntentionRejected(resolution_header, decision))
    return PolicyEventPhase(next_state, tuple(events))


def _validation_for_candidate(
    phase: PolicyValidationPhase,
    invocation_id: PolicyInvocationId,
) -> PolicyValidation:
    for validation in phase.validations:
        if validation.evaluation.invocation_id == invocation_id:
            return validation
    raise ValueError("policy arbitration candidate has no validation")


def _policy_event_id_for_invocation(
    event_ids: list[tuple[PolicyInvocationId, EventId]],
    invocation_id: PolicyInvocationId,
) -> EventId:
    for candidate_invocation_id, event_id in event_ids:
        if candidate_invocation_id == invocation_id:
            return event_id
    raise AssertionError("validated policy invocation has no policy event")


def _require_candidate_matches_validation(
    validation: PolicyValidation,
    decision: IntentionArbitration,
) -> None:
    if not validation.succeeded:
        raise ValueError("failed policy validation cannot produce an intention candidate")
    policy_order = decision.candidate.origin.policy_order
    if policy_order >= len(validation.intentions):
        raise ValueError("intention candidate policy order is outside its validation")
    if validation.intentions[policy_order] != decision.candidate.intention:
        raise ValueError("intention candidate does not match its validation")


def _allocate_event_header(
    state: MissionState,
    parent_event_ids: tuple[EventId, ...] = (),
) -> tuple[MissionState, EventHeader]:
    event_id, id_allocator = state.id_allocator.allocate_event()
    return replace(state, id_allocator=id_allocator), EventHeader(
        event_id,
        state.tick,
        parent_event_ids,
    )
