from __future__ import annotations

import pytest

from kiwi.domain.ids import EntityId, EventId, TraceNodeId
from kiwi.trace.comparison import (
    ConsequenceDifferenceKind,
    compare_consequences,
)
from kiwi.trace.model import CausalTrace, ConsequenceTrace, TraceConsequenceKind, TraceLevel


def test_consequence_comparison_reports_changed_logical_consequence() -> None:
    expected = _trace(((2, TraceConsequenceKind.INJURY, (1,), "injury 1 to 2"),))
    actual = _trace(((2, TraceConsequenceKind.INJURY, (1,), "injury 1 to 3"),), event_start=9)

    comparison = compare_consequences(expected, actual)

    assert not comparison.matches
    assert len(comparison.differences) == 1
    difference = comparison.differences[0]
    assert difference.kind is ConsequenceDifferenceKind.CHANGED
    assert difference.key.tick == 2
    assert difference.key.kind is TraceConsequenceKind.INJURY
    assert difference.key.subject_entity_ids == (EntityId(1),)


def test_consequence_comparison_reports_added_and_removed_keys_in_order() -> None:
    expected = _trace(
        (
            (0, TraceConsequenceKind.INJURY, (1,), "injury"),
            (2, TraceConsequenceKind.OBJECTIVE, (2,), "objective lost"),
        )
    )
    actual = _trace(
        (
            (0, TraceConsequenceKind.INJURY, (1,), "injury"),
            (1, TraceConsequenceKind.OBJECTIVE, (2,), "objective found"),
        )
    )

    comparison = compare_consequences(expected, actual)

    assert tuple(difference.kind for difference in comparison.differences) == (
        ConsequenceDifferenceKind.ADDED,
        ConsequenceDifferenceKind.REMOVED,
    )
    assert tuple(difference.key.tick for difference in comparison.differences) == (1, 2)


def test_consequence_comparison_ignores_event_and_trace_node_allocation_ids() -> None:
    expected = _trace(((2, TraceConsequenceKind.SYSTEM_FAULT, (), "fault"),))
    actual = _trace(
        ((2, TraceConsequenceKind.SYSTEM_FAULT, (), "fault"),),
        event_start=99,
        node_start=42,
    )

    comparison = compare_consequences(expected, actual)

    assert comparison.matches


def test_consequence_comparison_rejects_non_traces() -> None:
    trace = _trace(())

    with pytest.raises(TypeError, match="CausalTrace"):
        compare_consequences(trace, object())  # type: ignore[arg-type]


def _trace(
    specifications: tuple[tuple[int, TraceConsequenceKind, tuple[int, ...], str], ...],
    *,
    event_start: int = 1,
    node_start: int = 1,
) -> CausalTrace:
    records = tuple(
        ConsequenceTrace(
            TraceNodeId(node_start + index),
            tick,
            kind,
            tuple(EntityId(entity_id) for entity_id in subject_entity_ids),
            EventId(event_start + index),
            summary,
        )
        for index, (tick, kind, subject_entity_ids, summary) in enumerate(specifications)
    )
    return CausalTrace(b"c" * 32, TraceLevel.SUMMARY, records, ())
