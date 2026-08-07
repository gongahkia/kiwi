from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from kiwi.domain.ids import EntityId, EventId, IntentionId, PolicyInvocationId, TraceNodeId
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.sim.events import EventKind
from kiwi.sim.intentions import IntentionKind, IntentionOrigin
from kiwi.trace.format import encode_trace
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
    TraceResolutionStatus,
    WorldEventTrace,
)


def test_trace_query_command_renders_stable_retained_evidence(tmp_path: Path) -> None:
    trace_path = tmp_path / "fixture.ktrace"
    trace_path.write_bytes(encode_trace(_trace()))

    selected = _run_trace_query(trace_path, "why-selected", "1")
    rejected = _run_trace_query(trace_path, "why-not-selected", "2")
    failed = _run_trace_query(trace_path, "why-failed", "1")
    consequence = _run_trace_query(trace_path, "consequence-chain", "7")
    unavailable = _run_trace_query(trace_path, "why-selected", "99")

    assert selected.returncode == 0
    assert selected.stderr == ""
    assert selected.stdout == (
        "query: why-selected\n"
        "intention: 1\n"
        "source: trace-cli.dtr@0..1\n"
        "policy_order: 0\n"
        "status: selected\n"
        "world_events: 1\n"
    )
    assert rejected.returncode == 0
    assert rejected.stderr == ""
    assert rejected.stdout == (
        "query: why-not-selected\n"
        "intention: 2\n"
        "source: trace-cli.dtr@0..1\n"
        "policy_order: 1\n"
        "status: rejected\n"
        "reason: channel_occupied\n"
        "competing_intentions: 1\n"
        "world_events: 3\n"
    )
    assert failed.returncode == 0
    assert failed.stderr == ""
    assert failed.stdout == (
        "query: why-failed\n"
        "intention: 1\n"
        "source: trace-cli.dtr@0..1\n"
        "policy_order: 0\n"
        "failure: event=2 kind=fire_rejected summary='fire rejected'\n"
        "path: 2 -> 3 -> 4\n"
    )
    assert consequence.returncode == 0
    assert consequence.stderr == ""
    assert consequence.stdout == (
        "query: consequence-chain\n"
        "consequence: node=7 kind=injury event=2 summary='operative injured'\n"
        "causes:\n"
        "  node=4 world_event event=2 kind=fire_rejected summary='fire rejected'\n"
        "  node=3 world_event event=1 kind=intention_selected summary='intention selected'\n"
        "  node=2 intention_resolution intention=1 status=selected\n"
        "  node=1 intention intention=1 source=trace-cli.dtr@0..1\n"
        "causal_edges: 1, 2, 3, 6\n"
    )
    assert unavailable.returncode == 0
    assert unavailable.stderr == ""
    assert unavailable.stdout == "query: why-selected\nunavailable: intention_not_retained\n"


def test_trace_query_command_reports_invalid_packets_and_target_ids(tmp_path: Path) -> None:
    trace_path = tmp_path / "invalid.ktrace"
    trace_path.write_bytes(b"invalid")

    invalid_packet = _run_trace_query(trace_path, "why-selected", "1")
    invalid_target = _run_trace_query(trace_path, "why-selected", "0")

    assert invalid_packet.returncode == 1
    assert invalid_packet.stdout == ""
    assert (
        invalid_packet.stderr
        == f"{trace_path}: TR002_INVALID_MAGIC: trace packet magic is invalid\n"
    )
    assert invalid_target.returncode == 1
    assert invalid_target.stdout == ""
    assert invalid_target.stderr == "trace-query: target ID must be a positive integer\n"


def test_trace_query_uses_the_last_complete_backup_when_the_primary_is_corrupt(
    tmp_path: Path,
) -> None:
    trace_path = tmp_path / "fixture.ktrace"
    encoded = encode_trace(_trace())
    trace_path.with_name("fixture.ktrace.bak").write_bytes(encoded)
    trace_path.write_bytes(b"invalid")

    result = _run_trace_query(trace_path, "why-selected", "1")

    assert result.returncode == 0
    assert result.stderr == f"{trace_path}: recovered from {trace_path}.bak\n"
    assert result.stdout.startswith("query: why-selected\n")


def _run_trace_query(
    path: Path, query_name: str, target_id: str
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "kiwi.cli", "trace-query", str(path), query_name, target_id],
        capture_output=True,
        check=False,
        text=True,
    )


def _trace() -> CausalTrace:
    source = SourceFile(SourceFileId("trace-cli.dtr"), "x")
    span = source.span(ByteOffset(0), ByteOffset(1))
    selected_origin = IntentionOrigin(
        IntentionId(1),
        EntityId(1),
        PolicyInvocationId(1),
        ExpressionId(1),
        span,
        0,
        3,
        IntentionKind.FIRE,
    )
    rejected_origin = IntentionOrigin(
        IntentionId(2),
        EntityId(1),
        PolicyInvocationId(1),
        ExpressionId(2),
        span,
        1,
        3,
        IntentionKind.MOVE_TOWARD,
    )
    records = (
        IntentionTrace(TraceNodeId(1), 3, selected_origin),
        IntentionResolutionTrace(
            TraceNodeId(2),
            3,
            IntentionId(1),
            TraceResolutionStatus.SELECTED,
            None,
            (),
            (EventId(1),),
        ),
        WorldEventTrace(
            TraceNodeId(3),
            3,
            EventId(1),
            EventKind.INTENTION_SELECTED,
            "intention selected",
        ),
        WorldEventTrace(TraceNodeId(4), 3, EventId(2), EventKind.FIRE_REJECTED, "fire rejected"),
        IntentionTrace(TraceNodeId(5), 3, rejected_origin),
        IntentionResolutionTrace(
            TraceNodeId(6),
            3,
            IntentionId(2),
            TraceResolutionStatus.REJECTED,
            "channel_occupied",
            (IntentionId(1),),
            (EventId(3),),
        ),
        ConsequenceTrace(
            TraceNodeId(7),
            3,
            TraceConsequenceKind.INJURY,
            (EntityId(1),),
            EventId(2),
            "operative injured",
        ),
    )
    edges = (
        TraceEdge(TraceEdgeId(1), TraceNodeId(1), TraceNodeId(2), TraceEdgeKind.VALIDATED_BY),
        TraceEdge(TraceEdgeId(2), TraceNodeId(2), TraceNodeId(3), TraceEdgeKind.CAUSED_EVENT),
        TraceEdge(TraceEdgeId(3), TraceNodeId(3), TraceNodeId(4), TraceEdgeKind.CAUSED_EVENT),
        TraceEdge(TraceEdgeId(4), TraceNodeId(5), TraceNodeId(6), TraceEdgeKind.REJECTED_BECAUSE),
        TraceEdge(TraceEdgeId(5), TraceNodeId(1), TraceNodeId(6), TraceEdgeKind.SELECTED_OVER),
        TraceEdge(TraceEdgeId(6), TraceNodeId(4), TraceNodeId(7), TraceEdgeKind.CONTRIBUTED_TO),
    )
    return CausalTrace(b"c" * 32, TraceLevel.FULL, records, edges)
