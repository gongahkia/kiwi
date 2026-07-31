"""One fixed authoritative tick over the currently defined kernel state."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.sim.arbitration import arbitrate_intentions
from kiwi.sim.clock import FixedTickClock
from kiwi.sim.commands import (
    ExternalCommand,
    IssueSignal,
    RequestAbort,
    StartMission,
    canonical_command_order,
)
from kiwi.sim.contacts import advance_contacts
from kiwi.sim.events import (
    AbortRequested,
    CanonicalEvent,
    CommandRejected,
    CommandRejectionReason,
    EventHeader,
    MissionStarted,
    ScheduledTriggerFired,
    canonical_event_order,
)
from kiwi.sim.fallback import commit_policy_decisions, resolve_policy_decisions
from kiwi.sim.messages import discard_expired_messages
from kiwi.sim.movement import resolve_movement_actions
from kiwi.sim.movement_events import emit_movement_events
from kiwi.sim.movement_intentions import emit_movement_route_events, plan_selected_movement_routes
from kiwi.sim.policies import (
    EMPTY_POLICY_BINDINGS,
    PolicyBindings,
    invoke_policies,
    validate_policy_evaluations,
)
from kiwi.sim.policy_events import emit_policy_events
from kiwi.sim.state import MissionPhase, MissionState


@dataclass(frozen=True, slots=True)
class TickResult:
    """The successor authority state and canonical events from one tick."""

    state: MissionState
    events: tuple[CanonicalEvent, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("tick result requires mission state")
        if not isinstance(self.events, tuple):
            raise ValueError("tick result events must be an immutable tuple")
        if canonical_event_order(self.events) != self.events:
            raise ValueError("tick result events must be canonically ordered")


def reduce_one_tick(
    state: MissionState,
    clock: FixedTickClock,
    commands: tuple[ExternalCommand, ...] = (),
    policy_bindings: PolicyBindings = EMPTY_POLICY_BINDINGS,
) -> TickResult:
    """Apply exact-tick inputs, dequeue markers, emit events, and advance once."""
    if not isinstance(state, MissionState):
        raise ValueError("tick reduction requires mission state")
    if not isinstance(clock, FixedTickClock):
        raise ValueError("tick reduction requires a fixed tick clock")
    if not isinstance(commands, tuple):
        raise ValueError("tick reduction commands must be an immutable tuple")
    if not isinstance(policy_bindings, PolicyBindings):
        raise ValueError("tick reduction policy bindings must be policy bindings")
    ordered_commands = canonical_command_order(commands)
    for command in ordered_commands:
        if command.header.tick != state.tick:
            raise ValueError("tick reduction commands must target the current mission tick")

    next_state = state
    emitted: list[CanonicalEvent] = []
    for command in ordered_commands:
        next_state, event = _apply_command(next_state, command)
        emitted.append(event)

    due, scheduled_events = next_state.scheduled_events.due_at(next_state.tick)
    next_state = replace(next_state, scheduled_events=scheduled_events)
    for scheduled_event in due:
        next_state, header = _allocate_event_header(next_state)
        emitted.append(ScheduledTriggerFired(header, scheduled_event))

    if next_state.phase is MissionPhase.ACTIVE:
        next_state = replace(
            next_state,
            contacts=advance_contacts(next_state.contacts, next_state.tick),
            messages=discard_expired_messages(next_state.messages, next_state.tick),
        )
    if next_state.phase is MissionPhase.ACTIVE and policy_bindings.entries:
        next_state, policy_events = _reduce_policies(next_state, policy_bindings)
        emitted.extend(policy_events)
    if next_state.phase is MissionPhase.ACTIVE:
        movement = emit_movement_events(resolve_movement_actions(next_state))
        next_state = movement.state
        emitted.extend(movement.events)

    advanced_state = clock.advance(next_state)
    return TickResult(state=advanced_state, events=canonical_event_order(emitted))


def _reduce_policies(
    state: MissionState,
    bindings: PolicyBindings,
) -> tuple[MissionState, tuple[CanonicalEvent, ...]]:
    evaluations = invoke_policies(state, bindings)
    validations = validate_policy_evaluations(evaluations, bindings)
    decisions = resolve_policy_decisions(validations)
    arbitration = arbitrate_intentions(validations, bindings)
    policy_events = emit_policy_events(validations, arbitration)
    routes = emit_movement_route_events(
        plan_selected_movement_routes(policy_events.state, arbitration),
        policy_events.events,
    )
    return (
        commit_policy_decisions(routes.state, decisions, bindings),
        policy_events.events + routes.events,
    )


def _apply_command(
    state: MissionState, command: ExternalCommand
) -> tuple[MissionState, CanonicalEvent]:
    if isinstance(command, StartMission):
        if state.phase is MissionPhase.PREPARED:
            state = replace(state, phase=MissionPhase.ACTIVE)
            state, header = _allocate_event_header(state)
            return state, MissionStarted(header, command)
        return _reject_command(state, command, CommandRejectionReason.MISSION_NOT_PREPARED)
    if isinstance(command, RequestAbort):
        if state.phase is MissionPhase.ACTIVE:
            state = replace(state, phase=MissionPhase.ABORT_REQUESTED)
            state, header = _allocate_event_header(state)
            return state, AbortRequested(header, command)
        return _reject_command(state, command, CommandRejectionReason.MISSION_NOT_ACTIVE)
    if isinstance(command, IssueSignal):
        return _reject_command(state, command, CommandRejectionReason.SIGNALS_UNAVAILABLE)
    raise ValueError("tick reduction requires an external command")


def _reject_command(
    state: MissionState,
    command: ExternalCommand,
    reason: CommandRejectionReason,
) -> tuple[MissionState, CommandRejected]:
    state, header = _allocate_event_header(state)
    return state, CommandRejected(header, command, reason)


def _allocate_event_header(state: MissionState) -> tuple[MissionState, EventHeader]:
    event_id, id_allocator = state.id_allocator.allocate_event()
    return replace(state, id_allocator=id_allocator), EventHeader(event_id, state.tick)
