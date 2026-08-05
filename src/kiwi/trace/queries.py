"""Evidence-only causal-trace queries for intention selection and failure."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import IntentionId, TraceNodeId
from kiwi.sim.events import EventKind
from kiwi.sim.intentions import IntentionOrigin
from kiwi.trace.model import (
    CausalTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    TraceResolutionStatus,
    WorldEventTrace,
)

_FAILURE_EVENT_KINDS = frozenset(
    {
        EventKind.COVER_RESERVATION_REJECTED,
        EventKind.MOVEMENT_ROUTE_REJECTED,
        EventKind.MOVEMENT_BLOCKED,
        EventKind.FIRE_REJECTED,
    }
)


class TraceQueryUnavailableCode(StrEnum):
    """Closed reasons a retained trace cannot answer one query."""

    INTENTION_NOT_RETAINED = "intention_not_retained"
    RESOLUTION_NOT_RETAINED = "resolution_not_retained"
    INTENTION_NOT_SELECTED = "intention_not_selected"
    INTENTION_NOT_REJECTED = "intention_not_rejected"
    FAILURE_NOT_RETAINED = "failure_not_retained"


@dataclass(frozen=True, slots=True)
class TraceQueryUnavailable:
    """One explicit absence of retained evidence without an inferred answer."""

    code: TraceQueryUnavailableCode
    intention_id: IntentionId

    def __post_init__(self) -> None:
        if not isinstance(self.code, TraceQueryUnavailableCode):
            raise ValueError("trace query unavailable result requires a code")
        if not isinstance(self.intention_id, IntentionId):
            raise ValueError("trace query unavailable result requires an intention ID")


@dataclass(frozen=True, slots=True)
class IntentionSelectionExplanation:
    """One retained source origin and selected arbitration result."""

    origin: IntentionOrigin
    resolution: IntentionResolutionTrace

    def __post_init__(self) -> None:
        if not isinstance(self.origin, IntentionOrigin):
            raise ValueError("selection explanation requires an intention origin")
        if not isinstance(self.resolution, IntentionResolutionTrace):
            raise ValueError("selection explanation requires an intention resolution")
        if self.resolution.intention_id != self.origin.intention_id:
            raise ValueError("selection explanation origin must match its resolution")
        if self.resolution.status is not TraceResolutionStatus.SELECTED:
            raise ValueError("selection explanation requires a selected resolution")


@dataclass(frozen=True, slots=True)
class IntentionRejectionExplanation:
    """One retained source origin and arbitration rejection with competitors."""

    origin: IntentionOrigin
    resolution: IntentionResolutionTrace

    def __post_init__(self) -> None:
        if not isinstance(self.origin, IntentionOrigin):
            raise ValueError("rejection explanation requires an intention origin")
        if not isinstance(self.resolution, IntentionResolutionTrace):
            raise ValueError("rejection explanation requires an intention resolution")
        if self.resolution.intention_id != self.origin.intention_id:
            raise ValueError("rejection explanation origin must match its resolution")
        if self.resolution.status is not TraceResolutionStatus.REJECTED:
            raise ValueError("rejection explanation requires a rejected resolution")


@dataclass(frozen=True, slots=True)
class IntentionFailureExplanation:
    """One retained selected origin and first reachable execution-failure event."""

    origin: IntentionOrigin
    resolution: IntentionResolutionTrace
    failure_event: WorldEventTrace
    path_node_ids: tuple[TraceNodeId, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.origin, IntentionOrigin):
            raise ValueError("failure explanation requires an intention origin")
        if not isinstance(self.resolution, IntentionResolutionTrace):
            raise ValueError("failure explanation requires an intention resolution")
        if self.resolution.intention_id != self.origin.intention_id:
            raise ValueError("failure explanation origin must match its resolution")
        if self.resolution.status is not TraceResolutionStatus.SELECTED:
            raise ValueError("failure explanation requires a selected resolution")
        if not isinstance(self.failure_event, WorldEventTrace):
            raise ValueError("failure explanation requires a world event")
        if self.failure_event.event_kind not in _FAILURE_EVENT_KINDS:
            raise ValueError("failure explanation requires a failure event")
        if not isinstance(self.path_node_ids, tuple) or not self.path_node_ids:
            raise ValueError("failure explanation requires a non-empty path")
        if any(not isinstance(node_id, TraceNodeId) for node_id in self.path_node_ids):
            raise ValueError("failure explanation path requires trace node IDs")
        if self.path_node_ids[-1] != self.failure_event.node_id:
            raise ValueError("failure explanation path must end at its failure event")


type SelectionQueryResult = IntentionSelectionExplanation | TraceQueryUnavailable
type RejectionQueryResult = IntentionRejectionExplanation | TraceQueryUnavailable
type FailureQueryResult = IntentionFailureExplanation | TraceQueryUnavailable


def why_selected(trace: CausalTrace, intention_id: IntentionId) -> SelectionQueryResult:
    """Return retained evidence that one emitted intention won arbitration."""
    evidence = _origin_and_resolution(trace, intention_id)
    if isinstance(evidence, TraceQueryUnavailable):
        return evidence
    origin, resolution = evidence
    if resolution.status is not TraceResolutionStatus.SELECTED:
        return TraceQueryUnavailable(TraceQueryUnavailableCode.INTENTION_NOT_SELECTED, intention_id)
    return IntentionSelectionExplanation(origin.origin, resolution)


def why_not_selected(trace: CausalTrace, intention_id: IntentionId) -> RejectionQueryResult:
    """Return retained arbitration evidence that one emitted intention lost."""
    evidence = _origin_and_resolution(trace, intention_id)
    if isinstance(evidence, TraceQueryUnavailable):
        return evidence
    origin, resolution = evidence
    if resolution.status is not TraceResolutionStatus.REJECTED:
        return TraceQueryUnavailable(TraceQueryUnavailableCode.INTENTION_NOT_REJECTED, intention_id)
    return IntentionRejectionExplanation(origin.origin, resolution)


def why_failed(trace: CausalTrace, intention_id: IntentionId) -> FailureQueryResult:
    """Return the first retained causal execution failure after selected arbitration."""
    evidence = _origin_and_resolution(trace, intention_id)
    if isinstance(evidence, TraceQueryUnavailable):
        return evidence
    origin, resolution = evidence
    if resolution.status is not TraceResolutionStatus.SELECTED:
        return TraceQueryUnavailable(TraceQueryUnavailableCode.INTENTION_NOT_SELECTED, intention_id)
    failure = _first_failure(trace, (resolution.node_id, origin.node_id))
    if failure is None:
        return TraceQueryUnavailable(TraceQueryUnavailableCode.FAILURE_NOT_RETAINED, intention_id)
    failure_event, path = failure
    return IntentionFailureExplanation(origin.origin, resolution, failure_event, path)


def _origin_and_resolution(
    trace: CausalTrace,
    intention_id: IntentionId,
) -> tuple[IntentionTrace, IntentionResolutionTrace] | TraceQueryUnavailable:
    if not isinstance(trace, CausalTrace):
        raise TypeError("trace query requires a causal trace")
    if not isinstance(intention_id, IntentionId):
        raise TypeError("trace query requires an intention ID")
    origin = _intention_trace(trace, intention_id)
    if origin is None:
        return TraceQueryUnavailable(
            TraceQueryUnavailableCode.INTENTION_NOT_RETAINED,
            intention_id,
        )
    resolution = _resolution_trace(trace, intention_id)
    if resolution is None:
        return TraceQueryUnavailable(
            TraceQueryUnavailableCode.RESOLUTION_NOT_RETAINED,
            intention_id,
        )
    return origin, resolution


def _intention_trace(trace: CausalTrace, intention_id: IntentionId) -> IntentionTrace | None:
    for record in trace.records:
        if isinstance(record, IntentionTrace) and record.origin.intention_id == intention_id:
            return record
    return None


def _resolution_trace(
    trace: CausalTrace,
    intention_id: IntentionId,
) -> IntentionResolutionTrace | None:
    for record in trace.records:
        if isinstance(record, IntentionResolutionTrace) and record.intention_id == intention_id:
            return record
    return None


def _first_failure(
    trace: CausalTrace,
    root_node_ids: tuple[TraceNodeId, ...],
) -> tuple[WorldEventTrace, tuple[TraceNodeId, ...]] | None:
    records_by_node_id = {record.node_id: record for record in trace.records}
    outgoing_node_ids: dict[TraceNodeId, list[TraceNodeId]] = {}
    for edge in trace.edges:
        outgoing_node_ids.setdefault(edge.source_node_id, []).append(edge.target_node_id)
    queue: list[TraceNodeId] = []
    predecessors: dict[TraceNodeId, TraceNodeId | None] = {}
    for node_id in root_node_ids:
        if node_id not in predecessors:
            queue.append(node_id)
            predecessors[node_id] = None
    index = 0
    while index < len(queue):
        node_id = queue[index]
        index += 1
        record = records_by_node_id[node_id]
        if isinstance(record, WorldEventTrace) and record.event_kind in _FAILURE_EVENT_KINDS:
            return record, _path_to(node_id, predecessors)
        for target_node_id in outgoing_node_ids.get(node_id, ()):
            if target_node_id in predecessors:
                continue
            predecessors[target_node_id] = node_id
            queue.append(target_node_id)
    return None


def _path_to(
    node_id: TraceNodeId,
    predecessors: dict[TraceNodeId, TraceNodeId | None],
) -> tuple[TraceNodeId, ...]:
    path = [node_id]
    predecessor = predecessors[node_id]
    while predecessor is not None:
        path.append(predecessor)
        predecessor = predecessors[predecessor]
    path.reverse()
    return tuple(path)
