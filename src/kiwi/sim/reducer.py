"""One fixed authoritative tick over the currently defined kernel state."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.sim.aim import resolve_aim_progression
from kiwi.sim.arbitration import PolicyArbitrationPhase, arbitrate_intentions
from kiwi.sim.clock import FixedTickClock
from kiwi.sim.combat_events import (
    emit_damage_events,
    emit_fire_events,
    emit_projectile_events,
    emit_suppression_events,
)
from kiwi.sim.commands import (
    ExternalCommand,
    IssueSignal,
    RequestAbort,
    StartMission,
    canonical_command_order,
)
from kiwi.sim.communication import emit_message_delivery_events
from kiwi.sim.contacts import advance_contacts
from kiwi.sim.cover_events import emit_take_cover_events
from kiwi.sim.cover_intentions import resolve_selected_take_cover
from kiwi.sim.damage import resolve_projectile_damage
from kiwi.sim.events import (
    AbortRequested,
    CanonicalEvent,
    CommandRejected,
    CommandRejectionReason,
    EventHeader,
    LockdownActivated,
    MissionStarted,
    ObjectiveExtracted,
    ObjectiveRetrieved,
    ScheduledTriggerFired,
    SignalIssued,
    canonical_event_order,
)
from kiwi.sim.fallback import commit_policy_decisions, resolve_policy_decisions
from kiwi.sim.firing import resolve_selected_fire
from kiwi.sim.lockdown import LockdownState
from kiwi.sim.messages import discard_expired_messages
from kiwi.sim.movement import resolve_movement_actions
from kiwi.sim.movement_events import emit_movement_events
from kiwi.sim.movement_intentions import emit_movement_route_events, plan_selected_movement_routes
from kiwi.sim.objectives import (
    extracted_objective,
    extraction_ready,
    replace_objective,
    retrieval_candidate,
    retrieved_objective,
)
from kiwi.sim.policies import (
    EMPTY_POLICY_BINDINGS,
    PolicyBindings,
    invoke_policies,
    validate_policy_evaluations,
)
from kiwi.sim.policy_events import emit_policy_events
from kiwi.sim.projectile_impacts import resolve_projectile_impacts
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.signals import SignalObservation, add_signal, discard_signals_before
from kiwi.sim.state import MissionPhase, MissionState
from kiwi.sim.suppression import resolve_projectile_suppression


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

    next_state = replace(state, signals=discard_signals_before(state.signals, state.tick))
    emitted: list[CanonicalEvent] = []
    for command in ordered_commands:
        next_state, event = _apply_command(next_state, command)
        emitted.append(event)

    due, scheduled_events = next_state.scheduled_events.due_at(next_state.tick)
    next_state = replace(next_state, scheduled_events=scheduled_events)
    for scheduled_event in due:
        next_state, header = _allocate_event_header(next_state)
        trigger = ScheduledTriggerFired(header, scheduled_event)
        emitted.append(trigger)
        if scheduled_event.kind is ScheduledEventKind.LOCKDOWN:
            next_state, allocated_header = _allocate_event_header(next_state)
            lockdown_header = EventHeader(
                allocated_header.event_id,
                allocated_header.tick,
                (trigger.header.event_id,),
            )
            next_state = replace(
                next_state,
                lockdown=LockdownState(
                    True,
                    next_state.tick,
                    lockdown_header.event_id,
                ),
            )
            emitted.append(LockdownActivated(lockdown_header, scheduled_event))

    if next_state.phase is MissionPhase.ACTIVE:
        delivery = emit_message_delivery_events(next_state)
        next_state = replace(
            delivery.state,
            contacts=advance_contacts(next_state.contacts, next_state.tick),
            messages=discard_expired_messages(next_state.messages, next_state.tick),
        )
        emitted.extend(delivery.events)
    arbitration: PolicyArbitrationPhase | None = None
    if next_state.phase is MissionPhase.ACTIVE and policy_bindings.entries:
        next_state, policy_events, arbitration = _reduce_policies(next_state, policy_bindings)
        emitted.extend(policy_events)
    if next_state.phase is MissionPhase.ACTIVE:
        movement_phase = resolve_movement_actions(next_state)
        movement = emit_movement_events(movement_phase)
        emitted.extend(movement.events)
        aim = resolve_aim_progression(movement.state, clock, movement_phase.resolutions)
        firing = resolve_selected_fire(aim.state, arbitration) if arbitration is not None else None
        if firing is not None:
            fire_events = emit_fire_events(firing, tuple(emitted))
            after_firing = fire_events.state
            emitted.extend(fire_events.events)
        else:
            after_firing = aim.state
        source_projectiles = after_firing.projectiles.entries
        impacts = resolve_projectile_impacts(after_firing)
        projectile_events = emit_projectile_events(impacts)
        emitted.extend(projectile_events.events)
        damage = resolve_projectile_damage(projectile_events.state, impacts.impacts)
        damage_events = emit_damage_events(damage, projectile_events.events)
        emitted.extend(damage_events.events)
        suppression = resolve_projectile_suppression(
            damage_events.state,
            source_projectiles,
            impacts.impacts,
        )
        suppression_events = emit_suppression_events(suppression, projectile_events.events)
        next_state = suppression_events.state
        emitted.extend(suppression_events.events)
        next_state, objective_events = _resolve_objectives(next_state)
        emitted.extend(objective_events)

    advanced_state = clock.advance(next_state)
    return TickResult(state=advanced_state, events=canonical_event_order(emitted))


def _reduce_policies(
    state: MissionState,
    bindings: PolicyBindings,
) -> tuple[MissionState, tuple[CanonicalEvent, ...], PolicyArbitrationPhase]:
    evaluations = invoke_policies(state, bindings)
    validations = validate_policy_evaluations(evaluations, bindings)
    decisions = resolve_policy_decisions(validations)
    arbitration = arbitrate_intentions(validations, bindings)
    policy_events = emit_policy_events(validations, arbitration)
    cover_events = emit_take_cover_events(
        resolve_selected_take_cover(policy_events.state, arbitration),
        policy_events.events,
    )
    routes = emit_movement_route_events(
        plan_selected_movement_routes(cover_events.state, arbitration),
        policy_events.events,
    )
    return (
        commit_policy_decisions(routes.state, decisions, bindings),
        policy_events.events + cover_events.events + routes.events,
        arbitration,
    )


def _resolve_objectives(state: MissionState) -> tuple[MissionState, tuple[CanonicalEvent, ...]]:
    """Advance objective transitions after movement and combat leave positions stable."""
    emitted: list[CanonicalEvent] = []
    for objective in state.objectives.entries:
        retriever = retrieval_candidate(objective, state.entities)
        if retriever is not None:
            state, header = _allocate_event_header(state)
            updated = retrieved_objective(objective, retriever, header.event_id)
            state = replace(state, objectives=replace_objective(state.objectives, updated))
            emitted.append(ObjectiveRetrieved(header, updated))
            continue
        if not state.lockdown.active and extraction_ready(objective, state.entities):
            state, allocated_header = _allocate_event_header(state)
            updated = extracted_objective(objective)
            if updated.retrieval_event_id is None:
                raise AssertionError("retrieved objective lacks retrieval provenance")
            header = EventHeader(
                allocated_header.event_id,
                allocated_header.tick,
                (updated.retrieval_event_id,),
            )
            state = replace(state, objectives=replace_objective(state.objectives, updated))
            emitted.append(ObjectiveExtracted(header, updated))
    return state, tuple(emitted)


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
        if state.phase is not MissionPhase.ACTIVE:
            return _reject_command(state, command, CommandRejectionReason.MISSION_NOT_ACTIVE)
        if command.target is not None and command.target not in tuple(
            entity.entity_id for entity in state.entities
        ):
            return _reject_command(state, command, CommandRejectionReason.SIGNAL_TARGET_NOT_FOUND)
        state, header = _allocate_event_header(state)
        signal = SignalObservation(
            signal=command.signal,
            tick=state.tick,
            command_sequence=command.header.sequence,
            source=command.header.source,
            target_entity_id=command.target,
            provenance_event_id=header.event_id,
        )
        return replace(state, signals=add_signal(state.signals, signal)), SignalIssued(
            header, command
        )
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
