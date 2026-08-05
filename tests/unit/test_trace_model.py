from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.ids import EntityId, EventId, IntentionId, PolicyInvocationId, TraceNodeId
from kiwi.dsl.ids import ExpressionId, FunctionId
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.sim.events import EventKind
from kiwi.sim.intentions import IntentionKind, IntentionOrigin
from kiwi.trace.format import (
    TRACE_MAGIC,
    TRACE_VERSION,
    TraceDecodeFailure,
    TraceDecodeFailureCode,
    decode_trace,
    encode_trace,
    hash_trace,
)
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    ExpressionEvaluationTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    ObservationFactTrace,
    PolicyInvocationTrace,
    TraceConsequenceKind,
    TraceEdge,
    TraceEdgeId,
    TraceEdgeKind,
    TraceLevel,
    TraceResolutionStatus,
    WorldEventTrace,
)


def test_causal_trace_requires_ordered_retained_records_and_edges() -> None:
    trace = _trace()

    assert tuple(record.node_id.value for record in trace.records) == tuple(range(1, 8))
    assert tuple(edge.edge_id.value for edge in trace.edges) == tuple(range(1, 7))
    with pytest.raises(ValueError, match="node-ID ordered"):
        replace(trace, records=(trace.records[1], trace.records[0], *trace.records[2:]))
    with pytest.raises(ValueError, match="reference retained records"):
        replace(
            trace,
            edges=(
                TraceEdge(TraceEdgeId(1), TraceNodeId(1), TraceNodeId(8), TraceEdgeKind.READ_FROM),
            ),
        )


def test_trace_packet_round_trips_canonically_and_hashes_stably() -> None:
    trace = _trace()
    encoded = encode_trace(trace)

    decoded = decode_trace(encoded)

    assert decoded == trace
    assert encode_trace(trace) == encoded
    assert len(hash_trace(trace)) == 32
    assert hash_trace(trace) == hash_trace(trace)


def test_trace_packet_rejects_unsupported_and_noncanonical_bytes() -> None:
    encoded = encode_trace(_trace())

    unsupported = decode_trace(TRACE_MAGIC + (TRACE_VERSION - 1).to_bytes(2, "big") + b"{}")
    noncanonical = decode_trace(encoded + b" ")

    assert isinstance(unsupported, TraceDecodeFailure)
    assert unsupported.code is TraceDecodeFailureCode.UNSUPPORTED_VERSION
    assert isinstance(noncanonical, TraceDecodeFailure)
    assert noncanonical.code is TraceDecodeFailureCode.NONCANONICAL


def _trace() -> CausalTrace:
    source = SourceFile(SourceFileId("trace-test.dtr"), "x")
    span = source.span(ByteOffset(0), ByteOffset(1))
    origin = IntentionOrigin(
        IntentionId(1),
        EntityId(1),
        PolicyInvocationId(1),
        ExpressionId(1),
        span,
        0,
        0,
        IntentionKind.FIRE,
    )
    records = (
        PolicyInvocationTrace(
            TraceNodeId(1),
            0,
            EntityId(1),
            PolicyInvocationId(1),
            b"p" * 32,
            FunctionId(0),
            b"m" * 32,
            "success",
        ),
        ExpressionEvaluationTrace(
            TraceNodeId(2), 0, PolicyInvocationId(1), ExpressionId(1), span, "Fire request"
        ),
        ObservationFactTrace(
            TraceNodeId(3),
            0,
            PolicyInvocationId(1),
            ("nearest_contact",),
            "contact at 2.5m",
            (EventId(1),),
            7_500,
            1,
        ),
        IntentionTrace(TraceNodeId(4), 0, origin),
        IntentionResolutionTrace(
            TraceNodeId(5),
            0,
            IntentionId(1),
            TraceResolutionStatus.SELECTED,
            None,
            (),
            (EventId(1),),
        ),
        WorldEventTrace(TraceNodeId(6), 0, EventId(1), EventKind.FIRE_FIRED, "weapon fired"),
        ConsequenceTrace(
            TraceNodeId(7),
            0,
            TraceConsequenceKind.INJURY,
            (EntityId(1),),
            EventId(1),
            "operative injured",
        ),
    )
    edges = (
        TraceEdge(TraceEdgeId(1), TraceNodeId(3), TraceNodeId(2), TraceEdgeKind.READ_FROM),
        TraceEdge(TraceEdgeId(2), TraceNodeId(2), TraceNodeId(4), TraceEdgeKind.CONSTRUCTED),
        TraceEdge(TraceEdgeId(3), TraceNodeId(4), TraceNodeId(5), TraceEdgeKind.VALIDATED_BY),
        TraceEdge(TraceEdgeId(4), TraceNodeId(5), TraceNodeId(6), TraceEdgeKind.CAUSED_EVENT),
        TraceEdge(TraceEdgeId(5), TraceNodeId(6), TraceNodeId(7), TraceEdgeKind.CONTRIBUTED_TO),
        TraceEdge(TraceEdgeId(6), TraceNodeId(1), TraceNodeId(2), TraceEdgeKind.COMPUTED_FROM),
    )
    return CausalTrace(b"r" * 32, TraceLevel.FULL, records, edges)
