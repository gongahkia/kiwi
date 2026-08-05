"""Project canonical policy lifecycle events into decision-level causal traces."""

from __future__ import annotations

from kiwi.domain.ids import EventId, IntentionId, PolicyInvocationId, TraceNodeId
from kiwi.sim.events import (
    CanonicalEvent,
    InjuryChanged,
    IntentionEmitted,
    IntentionRejected,
    IntentionSelected,
    PolicyEvaluated,
    ProjectileImpacted,
    event_kind,
)
from kiwi.sim.hashing import StateHash, hash_canonical_state
from kiwi.sim.policy_events import PolicyEventPhase
from kiwi.sim.runner import HeadlessRun
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    TraceConsequenceKind,
    TraceEdge,
    TraceEdgeId,
    TraceEdgeKind,
    TraceLevel,
    TraceRecord,
    TraceResolutionStatus,
    WorldEventTrace,
)


def capture_policy_lifecycle_trace(
    phase: PolicyEventPhase,
    state_hash: StateHash,
) -> CausalTrace:
    """Capture source-linked intention resolutions from one canonical policy event phase."""
    if not isinstance(phase, PolicyEventPhase):
        raise TypeError("policy lifecycle trace capture requires a policy event phase")
    if not isinstance(state_hash, StateHash):
        raise TypeError("policy lifecycle trace capture requires a canonical state hash")
    if hash_canonical_state(phase.state) != state_hash:
        raise ValueError("policy lifecycle trace hash must match the event phase state")
    return _capture_policy_lifecycle_events(phase.events, state_hash)


def _capture_policy_lifecycle_events(
    events: tuple[CanonicalEvent, ...],
    state_hash: StateHash,
) -> CausalTrace:
    """Project one policy-only canonical event sequence into a decision trace."""

    policy_events: list[PolicyEvaluated] = []
    emitted_events: list[IntentionEmitted] = []
    resolution_events: list[IntentionSelected | IntentionRejected] = []
    for event in events:
        if isinstance(event, PolicyEvaluated):
            policy_events.append(event)
        elif isinstance(event, IntentionEmitted):
            emitted_events.append(event)
        elif isinstance(event, (IntentionSelected, IntentionRejected)):
            resolution_events.append(event)
        else:
            raise ValueError("policy lifecycle trace received a non-policy event")

    ordered_emitted_events = tuple(
        sorted(emitted_events, key=lambda event: event.candidate.origin.intention_id.value)
    )
    _require_unique_intention_ids(ordered_emitted_events)

    records: list[IntentionTrace | IntentionResolutionTrace] = []
    intention_nodes: list[tuple[IntentionId, TraceNodeId]] = []
    resolution_nodes: list[tuple[IntentionId, TraceNodeId]] = []
    resolutions: list[IntentionSelected | IntentionRejected] = []
    lifecycle_event_ids: list[tuple[IntentionId, tuple[EventId, ...]]] = []
    for emitted in ordered_emitted_events:
        origin = emitted.candidate.origin
        policy_event = _policy_event_for_invocation(policy_events, origin.invocation_id)
        _require_emission_matches_policy_event(emitted, policy_event)
        resolution = _resolution_for_intention(resolution_events, origin.intention_id)
        _require_resolution_matches_emission(resolution, emitted)
        intention_node_id = TraceNodeId(len(records) + 1)
        records.append(IntentionTrace(intention_node_id, origin.creation_tick, origin))
        intention_nodes.append((origin.intention_id, intention_node_id))
        resolutions.append(resolution)
        lifecycle_event_ids.append(
            (
                origin.intention_id,
                (policy_event.header.event_id, emitted.header.event_id, resolution.header.event_id),
            )
        )

    for resolution in resolutions:
        intention_id = resolution.resolution.candidate.origin.intention_id
        resolution_node_id = TraceNodeId(len(records) + 1)
        records.append(
            IntentionResolutionTrace(
                resolution_node_id,
                resolution.header.tick,
                intention_id,
                _trace_resolution_status(resolution),
                _reason_code(resolution),
                resolution.resolution.competing_intention_ids,
                _event_ids_for_intention(lifecycle_event_ids, intention_id),
            )
        )
        resolution_nodes.append((intention_id, resolution_node_id))

    edges: list[TraceEdge] = []
    for resolution in resolutions:
        intention_id = resolution.resolution.candidate.origin.intention_id
        source_node_id = _node_for_intention(intention_nodes, intention_id)
        target_node_id = _node_for_intention(resolution_nodes, intention_id)
        if isinstance(resolution, IntentionSelected):
            _append_edge(edges, source_node_id, target_node_id, TraceEdgeKind.VALIDATED_BY)
            continue
        _append_edge(edges, source_node_id, target_node_id, TraceEdgeKind.REJECTED_BECAUSE)
        for competing_intention_id in resolution.resolution.competing_intention_ids:
            _append_edge(
                edges,
                _node_for_intention(intention_nodes, competing_intention_id),
                target_node_id,
                TraceEdgeKind.SELECTED_OVER,
            )
    return CausalTrace(state_hash.digest, TraceLevel.DECISION, tuple(records), tuple(edges))


def capture_run_trace(run: HeadlessRun, state_hash: StateHash) -> CausalTrace:
    """Capture canonical world-event and current injury-consequence records for one run."""
    if not isinstance(run, HeadlessRun):
        raise TypeError("run trace capture requires a headless run")
    if not isinstance(state_hash, StateHash):
        raise TypeError("run trace capture requires a canonical state hash")
    if hash_canonical_state(run.state) != state_hash:
        raise ValueError("run trace hash must match the headless run state")

    policy_trace = _capture_policy_lifecycle_events(
        tuple(
            event
            for event in run.events
            if isinstance(
                event,
                (PolicyEvaluated, IntentionEmitted, IntentionSelected, IntentionRejected),
            )
        ),
        state_hash,
    )
    records: list[TraceRecord] = list(policy_trace.records)
    world_nodes: list[tuple[EventId, TraceNodeId]] = []
    injury_nodes: list[tuple[InjuryChanged, TraceNodeId]] = []
    for event in run.events:
        node_id = TraceNodeId(len(records) + 1)
        kind = event_kind(event)
        records.append(
            WorldEventTrace(
                node_id,
                event.header.tick,
                event.header.event_id,
                kind,
                kind.value.replace("_", " "),
            )
        )
        world_nodes.append((event.header.event_id, node_id))
        if isinstance(event, InjuryChanged):
            injury_nodes.append((event, node_id))

    consequence_nodes: list[tuple[TraceNodeId, TraceNodeId]] = []
    for injury, world_node_id in injury_nodes:
        consequence_node_id = TraceNodeId(len(records) + 1)
        records.append(
            ConsequenceTrace(
                consequence_node_id,
                injury.header.tick,
                TraceConsequenceKind.INJURY,
                (injury.resolution.target_entity_id,),
                injury.header.event_id,
                "injury changed from "
                f"{injury.resolution.injury_before.value} to "
                f"{injury.resolution.injury_after.value}",
            )
        )
        consequence_nodes.append((world_node_id, consequence_node_id))

    edges = list(policy_trace.edges)
    _append_policy_resolution_event_edges(edges, policy_trace.records, world_nodes)
    _append_world_parent_edges(edges, run.events, world_nodes)
    _append_projectile_origin_edges(edges, run.events, policy_trace.records, world_nodes)
    for world_node_id, consequence_node_id in consequence_nodes:
        _append_edge(edges, world_node_id, consequence_node_id, TraceEdgeKind.CONTRIBUTED_TO)
    return CausalTrace(state_hash.digest, TraceLevel.DECISION, tuple(records), tuple(edges))


def _require_unique_intention_ids(events: tuple[IntentionEmitted, ...]) -> None:
    previous_intention_id = 0
    for event in events:
        intention_id = event.candidate.origin.intention_id.value
        if intention_id <= previous_intention_id:
            raise ValueError("policy lifecycle trace requires unique intention candidates")
        previous_intention_id = intention_id


def _policy_event_for_invocation(
    events: list[PolicyEvaluated],
    invocation_id: PolicyInvocationId,
) -> PolicyEvaluated:
    for event in events:
        if event.validation.evaluation.invocation_id == invocation_id:
            return event
    raise ValueError("intention emission has no policy evaluation event")


def _require_emission_matches_policy_event(
    emitted: IntentionEmitted,
    policy_event: PolicyEvaluated,
) -> None:
    validation = policy_event.validation
    origin = emitted.candidate.origin
    if emitted.header.parent_event_ids != (policy_event.header.event_id,):
        raise ValueError("intention emission must parent its policy evaluation")
    if not validation.succeeded:
        raise ValueError("failed policy evaluation cannot emit an intention")
    if origin.policy_order >= len(validation.intentions):
        raise ValueError("intention origin policy order is outside its validation")
    if validation.intentions[origin.policy_order] != emitted.candidate.intention:
        raise ValueError("intention emission does not match its validation")


def _resolution_for_intention(
    events: list[IntentionSelected | IntentionRejected],
    intention_id: IntentionId,
) -> IntentionSelected | IntentionRejected:
    matching_event: IntentionSelected | IntentionRejected | None = None
    for event in events:
        if event.resolution.candidate.origin.intention_id != intention_id:
            continue
        if matching_event is not None:
            raise ValueError("intention has multiple arbitration resolution events")
        matching_event = event
    if matching_event is None:
        raise ValueError("intention emission has no arbitration resolution event")
    return matching_event


def _require_resolution_matches_emission(
    resolution: IntentionSelected | IntentionRejected,
    emitted: IntentionEmitted,
) -> None:
    if resolution.header.parent_event_ids != (emitted.header.event_id,):
        raise ValueError("arbitration resolution must parent its intention emission")
    if resolution.resolution.candidate != emitted.candidate:
        raise ValueError("arbitration resolution does not match its intention emission")


def _trace_resolution_status(
    resolution: IntentionSelected | IntentionRejected,
) -> TraceResolutionStatus:
    if isinstance(resolution, IntentionSelected):
        return TraceResolutionStatus.SELECTED
    return TraceResolutionStatus.REJECTED


def _reason_code(resolution: IntentionSelected | IntentionRejected) -> str | None:
    if isinstance(resolution, IntentionSelected):
        return None
    reason = resolution.resolution.reason
    if reason is None:
        raise AssertionError("rejected arbitration must retain a reason")
    return reason.value


def _node_for_intention(
    nodes: list[tuple[IntentionId, TraceNodeId]],
    intention_id: IntentionId,
) -> TraceNodeId:
    for candidate_id, node_id in nodes:
        if candidate_id == intention_id:
            return node_id
    raise ValueError("intention trace edge references an unretained intention")


def _event_ids_for_intention(
    lifecycle_event_ids: list[tuple[IntentionId, tuple[EventId, ...]]],
    intention_id: IntentionId,
) -> tuple[EventId, ...]:
    for candidate_id, event_ids in lifecycle_event_ids:
        if candidate_id == intention_id:
            return event_ids
    raise AssertionError("retained intention has no policy lifecycle event IDs")


def _append_policy_resolution_event_edges(
    edges: list[TraceEdge],
    records: tuple[TraceRecord, ...],
    world_nodes: list[tuple[EventId, TraceNodeId]],
) -> None:
    for record in records:
        if not isinstance(record, IntentionResolutionTrace):
            continue
        _append_edge_if_retained(
            edges,
            record.node_id,
            _node_for_event(world_nodes, record.world_event_ids[-1]),
            TraceEdgeKind.CAUSED_EVENT,
        )


def _append_world_parent_edges(
    edges: list[TraceEdge],
    events: tuple[CanonicalEvent, ...],
    world_nodes: list[tuple[EventId, TraceNodeId]],
) -> None:
    for event in events:
        target_node_id = _node_for_event(world_nodes, event.header.event_id)
        if target_node_id is None:
            raise AssertionError("retained world event has no trace node")
        for parent_event_id in event.header.parent_event_ids:
            _append_edge_if_retained(
                edges,
                _node_for_event(world_nodes, parent_event_id),
                target_node_id,
                TraceEdgeKind.CAUSED_EVENT,
            )


def _append_projectile_origin_edges(
    edges: list[TraceEdge],
    events: tuple[CanonicalEvent, ...],
    records: tuple[TraceRecord, ...],
    world_nodes: list[tuple[EventId, TraceNodeId]],
) -> None:
    for event in events:
        if not isinstance(event, ProjectileImpacted):
            continue
        source_node_id = _node_for_trace_intention(
            records,
            event.impact.source_intention.intention_id,
        )
        target_node_id = _node_for_event(world_nodes, event.header.event_id)
        _append_edge_if_retained(edges, source_node_id, target_node_id, TraceEdgeKind.CAUSED_EVENT)


def _node_for_event(
    nodes: list[tuple[EventId, TraceNodeId]],
    event_id: EventId,
) -> TraceNodeId | None:
    for candidate_id, node_id in nodes:
        if candidate_id == event_id:
            return node_id
    return None


def _node_for_trace_intention(
    records: tuple[TraceRecord, ...],
    intention_id: IntentionId,
) -> TraceNodeId | None:
    for record in records:
        if isinstance(record, IntentionTrace) and record.origin.intention_id == intention_id:
            return record.node_id
    return None


def _append_edge_if_retained(
    edges: list[TraceEdge],
    source_node_id: TraceNodeId | None,
    target_node_id: TraceNodeId | None,
    kind: TraceEdgeKind,
) -> None:
    if source_node_id is not None and target_node_id is not None:
        _append_edge(edges, source_node_id, target_node_id, kind)


def _append_edge(
    edges: list[TraceEdge],
    source_node_id: TraceNodeId,
    target_node_id: TraceNodeId,
    kind: TraceEdgeKind,
) -> None:
    edges.append(TraceEdge(TraceEdgeId(len(edges) + 1), source_node_id, target_node_id, kind))
