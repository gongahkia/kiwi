"""Route selected move intentions into canonical movement actions."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.domain.geometry import WorldPosition
from kiwi.domain.ids import EventId, IntentionId
from kiwi.sim.arbitration import ArbitrationStatus, IntentionCandidate, PolicyArbitrationPhase
from kiwi.sim.events import (
    CanonicalEvent,
    EventHeader,
    IntentionSelected,
    MovementRouteRejected,
    MovementRouteStarted,
    canonical_event_order,
)
from kiwi.sim.intentions import MoveTowardIntention
from kiwi.sim.pathing import (
    Path,
    PathQueryFailure,
    PathSearchFailure,
    find_path,
    prepare_path_query,
)
from kiwi.sim.state import EntityState, MissionState, MovementAction

type RoutePlanningFailure = PathQueryFailure | PathSearchFailure
type RoutePlanningResult = Path | RoutePlanningFailure


@dataclass(frozen=True, slots=True)
class MovementRoutePlan:
    """One selected move request and its deterministic route planning result."""

    candidate: IntentionCandidate
    result: RoutePlanningResult

    def __post_init__(self) -> None:
        if not isinstance(self.candidate, IntentionCandidate):
            raise ValueError("movement route plan requires an intention candidate")
        if not isinstance(self.candidate.intention, MoveTowardIntention):
            raise ValueError("movement route plan requires a move-toward intention")
        if not isinstance(self.result, (Path, PathQueryFailure, PathSearchFailure)):
            raise ValueError("movement route plan requires a path or structured path failure")


@dataclass(frozen=True, slots=True)
class MovementRoutePlanningPhase:
    """The ordered planning results for newly selected movement targets."""

    state: MissionState
    plans: tuple[MovementRoutePlan, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("movement route planning requires mission state")
        if not isinstance(self.plans, tuple):
            raise ValueError("movement route plans must be an immutable tuple")
        previous_intention_id = 0
        for plan in self.plans:
            if not isinstance(plan, MovementRoutePlan):
                raise ValueError("movement route plans must contain route plans")
            intention_id = plan.candidate.origin.intention_id.value
            if intention_id <= previous_intention_id:
                raise ValueError("movement route plans must be intention-ID ordered")
            previous_intention_id = intention_id


@dataclass(frozen=True, slots=True)
class MovementRouteEventPhase:
    """The successor state and route activation events for one policy pass."""

    state: MissionState
    events: tuple[CanonicalEvent, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("movement route events require mission state")
        if not isinstance(self.events, tuple):
            raise ValueError("movement route events must be an immutable tuple")
        if canonical_event_order(self.events) != self.events:
            raise ValueError("movement route events must be canonically ordered")


def plan_selected_movement_routes(
    state: MissionState,
    arbitration: PolicyArbitrationPhase,
) -> MovementRoutePlanningPhase:
    """Plan only selected new move targets, retaining an action already en route."""
    if not isinstance(state, MissionState):
        raise TypeError("movement route planning requires mission state")
    if not isinstance(arbitration, PolicyArbitrationPhase):
        raise TypeError("movement route planning requires an arbitration phase")
    if state.tick != arbitration.state.tick:
        raise ValueError("movement route planning phases must share a mission tick")
    plans: list[MovementRoutePlan] = []
    for decision in arbitration.decisions:
        if decision.status is not ArbitrationStatus.SELECTED:
            continue
        candidate = decision.candidate
        if not isinstance(candidate.intention, MoveTowardIntention):
            continue
        entity = _entity_for_candidate(state, candidate)
        target = WorldPosition(
            candidate.intention.target.x,
            candidate.intention.target.y,
            entity.position.elevation,
        )
        active = _action_for_entity(state, candidate.origin.issuer_entity_id.value)
        if active is not None and active.path.query.goal == target:
            continue
        query = prepare_path_query(state.map_geometry, entity.position, target)
        if isinstance(query, PathQueryFailure):
            plans.append(MovementRoutePlan(candidate, query))
            continue
        plans.append(MovementRoutePlan(candidate, find_path(query)))
    return MovementRoutePlanningPhase(state, tuple(plans))


def emit_movement_route_events(
    phase: MovementRoutePlanningPhase,
    policy_events: tuple[CanonicalEvent, ...],
) -> MovementRouteEventPhase:
    """Emit source-linked route results and activate each successful path."""
    if not isinstance(phase, MovementRoutePlanningPhase):
        raise TypeError("movement route event emission requires a planning phase")
    if not isinstance(policy_events, tuple):
        raise TypeError("movement route event emission requires immutable policy events")
    next_state = phase.state
    events: list[CanonicalEvent] = []
    for plan in phase.plans:
        selected_event_id = _selected_event_id(policy_events, plan.candidate.origin.intention_id)
        event_id, id_allocator = next_state.id_allocator.allocate_event()
        next_state = replace(next_state, id_allocator=id_allocator)
        header = EventHeader(event_id, next_state.tick, (selected_event_id,))
        if isinstance(plan.result, Path):
            events.append(MovementRouteStarted(header, plan.candidate, plan.result))
            if len(plan.result.waypoints) > 1:
                next_state = _replace_movement_action(
                    next_state,
                    MovementAction(
                        plan.candidate.origin.issuer_entity_id,
                        plan.result,
                        origin_event_id=event_id,
                    ),
                )
            else:
                next_state = _remove_movement_action(
                    next_state,
                    plan.candidate.origin.issuer_entity_id.value,
                )
        else:
            events.append(MovementRouteRejected(header, plan.candidate, plan.result))
    return MovementRouteEventPhase(next_state, tuple(events))


def _entity_for_candidate(state: MissionState, candidate: IntentionCandidate) -> EntityState:
    for entity in state.entities:
        if entity.entity_id == candidate.origin.issuer_entity_id:
            return entity
    raise ValueError("selected movement intention issuer is not a mission entity")


def _action_for_entity(state: MissionState, entity_id: int) -> MovementAction | None:
    for action in state.movement_actions:
        if action.entity_id.value == entity_id:
            return action
    return None


def _replace_movement_action(state: MissionState, action: MovementAction) -> MissionState:
    retained = tuple(
        current for current in state.movement_actions if current.entity_id != action.entity_id
    )
    actions = tuple(sorted(retained + (action,), key=lambda current: current.entity_id.value))
    return replace(state, movement_actions=actions)


def _remove_movement_action(state: MissionState, entity_id: int) -> MissionState:
    return replace(
        state,
        movement_actions=tuple(
            action for action in state.movement_actions if action.entity_id.value != entity_id
        ),
    )


def _selected_event_id(events: tuple[CanonicalEvent, ...], intention_id: IntentionId) -> EventId:
    for event in events:
        if (
            isinstance(event, IntentionSelected)
            and event.resolution.candidate.origin.intention_id == intention_id
        ):
            return event.header.event_id
    raise ValueError("movement route plan requires a selected intention event")
