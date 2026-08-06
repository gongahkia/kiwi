"""Immutable mission-timeline projection from retained causal trace records."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.domain.ids import TraceNodeId
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    ExpressionEvaluationTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    ObservationFactTrace,
    PolicyInvocationTrace,
    TraceRecord,
    WorldEventTrace,
    trace_record_id,
)


class TimelineEntryKind(StrEnum):
    POLICY = "policy"
    EXPRESSION = "expression"
    OBSERVATION = "observation"
    INTENTION = "intention"
    RESOLUTION = "resolution"
    WORLD_EVENT = "world_event"
    CONSEQUENCE = "consequence"


@dataclass(frozen=True, slots=True)
class TimelineEntry:
    node_id: TraceNodeId
    tick: int
    kind: TimelineEntryKind
    summary: str

    def __post_init__(self) -> None:
        if not isinstance(self.node_id, TraceNodeId):
            raise TypeError("timeline entry requires a trace node ID")
        if not isinstance(self.tick, int) or isinstance(self.tick, bool) or self.tick < 0:
            raise ValueError("timeline entry tick must be non-negative")
        if not isinstance(self.kind, TimelineEntryKind):
            raise TypeError("timeline entry requires a timeline entry kind")
        if not isinstance(self.summary, str) or not self.summary:
            raise ValueError("timeline entry summary must be non-empty")


@dataclass(frozen=True, slots=True)
class MissionTimeline:
    trace_hash: bytes
    entries: tuple[TimelineEntry, ...]
    selected_node_id: TraceNodeId | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.trace_hash, bytes) or len(self.trace_hash) != 32:
            raise ValueError("mission timeline requires a 32-byte trace hash")
        if not isinstance(self.entries, tuple) or any(
            not isinstance(entry, TimelineEntry) for entry in self.entries
        ):
            raise TypeError("mission timeline entries must be a tuple of timeline entries")
        keys = tuple((entry.tick, entry.node_id.value) for entry in self.entries)
        if keys != tuple(sorted(keys)) or len({entry.node_id for entry in self.entries}) != len(
            self.entries
        ):
            raise ValueError("mission timeline entries must be unique and chronologically ordered")
        if self.selected_node_id is not None and self.selected_node_id not in tuple(
            entry.node_id for entry in self.entries
        ):
            raise ValueError("mission timeline selection is not retained")

    def select(self, node_id: TraceNodeId) -> MissionTimeline:
        if not isinstance(node_id, TraceNodeId):
            raise TypeError("mission timeline selection requires a trace node ID")
        return replace(self, selected_node_id=node_id)


def mission_timeline(trace: CausalTrace) -> MissionTimeline:
    if not isinstance(trace, CausalTrace):
        raise TypeError("mission timeline requires a causal trace")
    entries = tuple(
        sorted(
            (_timeline_entry(record) for record in trace.records),
            key=lambda entry: (entry.tick, entry.node_id.value),
        )
    )
    return MissionTimeline(trace.run_state_hash, entries)


def _timeline_entry(record: TraceRecord) -> TimelineEntry:
    node_id = trace_record_id(record)
    if isinstance(record, PolicyInvocationTrace):
        return TimelineEntry(node_id, record.tick, TimelineEntryKind.POLICY, record.result_summary)
    if isinstance(record, ExpressionEvaluationTrace):
        return TimelineEntry(
            node_id, record.tick, TimelineEntryKind.EXPRESSION, record.value_summary
        )
    if isinstance(record, ObservationFactTrace):
        return TimelineEntry(
            node_id,
            record.tick,
            TimelineEntryKind.OBSERVATION,
            f"{'.'.join(record.path)}: {record.value_summary}",
        )
    if isinstance(record, IntentionTrace):
        return TimelineEntry(
            node_id, record.tick, TimelineEntryKind.INTENTION, record.origin.kind.value
        )
    if isinstance(record, IntentionResolutionTrace):
        reason = f" ({record.reason_code})" if record.reason_code is not None else ""
        return TimelineEntry(
            node_id, record.tick, TimelineEntryKind.RESOLUTION, f"{record.status.value}{reason}"
        )
    if isinstance(record, WorldEventTrace):
        return TimelineEntry(node_id, record.tick, TimelineEntryKind.WORLD_EVENT, record.summary)
    if isinstance(record, ConsequenceTrace):
        return TimelineEntry(node_id, record.tick, TimelineEntryKind.CONSEQUENCE, record.summary)
    raise AssertionError("unsupported retained trace record")
