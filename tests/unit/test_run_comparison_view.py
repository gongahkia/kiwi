from __future__ import annotations

from dataclasses import replace

from kiwi.domain.ids import EntityId, EventId, TraceNodeId
from kiwi.replay.comparison import PolicyExecutionComparison
from kiwi.replay.compatibility import (
    PolicyVersionDifference,
    PolicyVersionDifferenceKind,
    RunCompatibility,
)
from kiwi.replay.recording import RecordedReplay, record_headless_run
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.policy_versions import PolicyVersion
from kiwi.sim.state import MissionState
from kiwi.trace.comparison import ConsequenceComparison
from kiwi.trace.model import CausalTrace, ConsequenceTrace, TraceConsequenceKind, TraceLevel
from kiwi.ui.run_comparison import RunComparisonView, run_comparison_view


def test_run_comparison_view_projects_compatible_run_deltas() -> None:
    expected, actual, expected_trace, actual_trace = _comparison_inputs()

    comparison = run_comparison_view(expected, actual, expected_trace, actual_trace)

    assert comparison.compatibility.is_compatible
    assert comparison.policy_execution is not None
    assert comparison.policy_execution.matches
    assert comparison.consequences is not None
    assert not comparison.consequences.matches
    assert not comparison.is_identical


def test_run_comparison_view_blocks_outcome_deltas_for_incompatible_baselines() -> None:
    expected, actual, expected_trace, actual_trace = _comparison_inputs()
    incompatible = RecordedReplay(
        replace(actual.replay, application_build="different-build"),
        actual.run,
    )

    comparison = run_comparison_view(expected, incompatible, expected_trace, actual_trace)

    assert not comparison.compatibility.is_compatible
    assert comparison.policy_execution is None
    assert comparison.consequences is None
    assert comparison.state_divergence is None


def test_run_comparison_view_does_not_call_policy_version_delta_identical() -> None:
    comparison = RunComparisonView(
        RunCompatibility(
            (),
            (
                PolicyVersionDifference(
                    EntityId(1),
                    PolicyVersionDifferenceKind.CHANGED,
                    PolicyVersion(b"a" * 32),
                    PolicyVersion(b"b" * 32),
                ),
            ),
        ),
        PolicyExecutionComparison(None, None),
        ConsequenceComparison(()),
        None,
    )

    assert not comparison.is_identical


def _comparison_inputs() -> tuple[RecordedReplay, RecordedReplay, CausalTrace, CausalTrace]:
    expected = record_headless_run(
        MissionState(),
        FixedTickClock(TickRate.HZ_30),
        1,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
    )
    actual = record_headless_run(
        MissionState(),
        FixedTickClock(TickRate.HZ_30),
        1,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
    )
    expected_trace = _trace(expected, "injury before")
    actual_trace = _trace(actual, "injury after")
    return expected, actual, expected_trace, actual_trace


def _trace(recorded: RecordedReplay, summary: str) -> CausalTrace:
    return CausalTrace(
        hash_canonical_state(recorded.run.state).digest,
        TraceLevel.SUMMARY,
        (
            ConsequenceTrace(
                TraceNodeId(1),
                1,
                TraceConsequenceKind.SYSTEM_FAULT,
                (),
                EventId(1),
                summary,
            ),
        ),
        (),
    )
