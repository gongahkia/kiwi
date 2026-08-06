"""Immutable run-comparison projections gated by replay baseline compatibility."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.replay.comparison import PolicyExecutionComparison, compare_policy_execution
from kiwi.replay.compatibility import RunCompatibility, check_run_compatibility
from kiwi.replay.recording import RecordedReplay
from kiwi.sim.determinism import DeterminismDivergence, compare_headless_runs
from kiwi.sim.hashing import hash_canonical_state
from kiwi.trace.comparison import ConsequenceComparison, compare_consequences
from kiwi.trace.model import CausalTrace


@dataclass(frozen=True, slots=True)
class RunComparisonView:
    compatibility: RunCompatibility
    policy_execution: PolicyExecutionComparison | None
    consequences: ConsequenceComparison | None
    state_divergence: DeterminismDivergence | None

    def __post_init__(self) -> None:
        if not isinstance(self.compatibility, RunCompatibility):
            raise TypeError("run comparison view requires replay compatibility")
        if self.compatibility.is_compatible:
            if not isinstance(self.policy_execution, PolicyExecutionComparison):
                raise ValueError("compatible run comparison requires policy execution comparison")
            if not isinstance(self.consequences, ConsequenceComparison):
                raise ValueError("compatible run comparison requires consequence comparison")
            if self.state_divergence is not None and not isinstance(
                self.state_divergence, DeterminismDivergence
            ):
                raise TypeError("run comparison state divergence is invalid")
        elif any(
            value is not None
            for value in (self.policy_execution, self.consequences, self.state_divergence)
        ):
            raise ValueError("incompatible run comparison must not project outcome differences")

    @property
    def is_identical(self) -> bool:
        """Return whether compatible runs have no retained policy, state, or consequence deltas."""
        if not self.compatibility.is_compatible:
            return False
        if self.policy_execution is None or self.consequences is None:
            raise AssertionError("compatible run comparison has incomplete projections")
        return (
            not self.compatibility.policy_differences
            and self.policy_execution.matches
            and self.consequences.matches
            and self.state_divergence is None
        )


def run_comparison_view(
    expected: RecordedReplay,
    actual: RecordedReplay,
    expected_trace: CausalTrace,
    actual_trace: CausalTrace,
) -> RunComparisonView:
    """Build a read-only comparison only after baseline compatibility succeeds."""
    if not isinstance(expected, RecordedReplay) or not isinstance(actual, RecordedReplay):
        raise TypeError("run comparison view requires recorded replays")
    if not isinstance(expected_trace, CausalTrace) or not isinstance(actual_trace, CausalTrace):
        raise TypeError("run comparison view requires causal traces")
    _require_trace_matches_run(expected_trace, expected)
    _require_trace_matches_run(actual_trace, actual)
    compatibility = check_run_compatibility(expected.replay, actual.replay)
    if not compatibility.is_compatible:
        return RunComparisonView(compatibility, None, None, None)
    return RunComparisonView(
        compatibility,
        compare_policy_execution(expected.run, actual.run),
        compare_consequences(expected_trace, actual_trace),
        compare_headless_runs(expected.run, actual.run),
    )


def _require_trace_matches_run(trace: CausalTrace, recorded: RecordedReplay) -> None:
    if trace.run_state_hash != hash_canonical_state(recorded.run.state).digest:
        raise ValueError("run comparison trace does not match its recorded final state")
