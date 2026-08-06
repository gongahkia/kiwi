"""Controlled headless Glasshouse reruns and compatibility-gated comparison."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.app.glasshouse_execution import (
    GlasshouseMissionExecution,
    build_glasshouse_mission_execution,
)
from kiwi.app.glasshouse_players import GlasshousePolicyFailure
from kiwi.content.missions import MissionData
from kiwi.dsl.source import SourceFile
from kiwi.replay.format import MAX_REPLAY_TEXT_BYTES
from kiwi.replay.recording import RecordedReplay, record_headless_run
from kiwi.replay.source_archive import (
    HistoricalSourceFile,
    ReplaySourceArchive,
    build_source_archive,
    source_archive_matches_replay,
)
from kiwi.sim.clock import FixedTickClock
from kiwi.sim.commands import ExternalCommand, canonical_command_order
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.policies import PolicyBindings
from kiwi.sim.policy_versions import EntityPolicyVersion
from kiwi.sim.snapshot import capture_authority_snapshot
from kiwi.sim.state import MissionState
from kiwi.trace.capture import capture_run_trace
from kiwi.trace.model import CausalTrace
from kiwi.ui.glasshouse_workbench import GlasshouseWorkbench
from kiwi.ui.run_comparison import RunComparisonView, run_comparison_view


class GlasshouseRerunUnavailableCode(StrEnum):
    INITIAL_STATE_CHANGED = "initial_state_changed"


@dataclass(frozen=True, slots=True)
class GlasshouseRerunUnavailable:
    code: GlasshouseRerunUnavailableCode

    def __post_init__(self) -> None:
        if not isinstance(self.code, GlasshouseRerunUnavailableCode):
            raise TypeError("Glasshouse rerun unavailable result requires a code")


@dataclass(frozen=True, slots=True)
class GlasshouseReplayIdentity:
    application_build: str
    simulation_version: str
    mission_hash: bytes

    def __post_init__(self) -> None:
        _validate_identifier(self.application_build, "Glasshouse replay application build")
        _validate_identifier(self.simulation_version, "Glasshouse replay simulation version")
        if not isinstance(self.mission_hash, bytes) or len(self.mission_hash) != 32:
            raise ValueError("Glasshouse replay mission hash must be exactly 32 bytes")


@dataclass(frozen=True, slots=True)
class GlasshouseControlledRun:
    initial_state: MissionState
    clock: FixedTickClock
    policy_bindings: PolicyBindings
    policy_sources: tuple[SourceFile, ...]
    commands: tuple[ExternalCommand, ...]
    ticks: int
    identity: GlasshouseReplayIdentity
    recorded: RecordedReplay
    trace: CausalTrace
    source_archive: ReplaySourceArchive

    def __post_init__(self) -> None:
        if not isinstance(self.initial_state, MissionState):
            raise TypeError("Glasshouse controlled run requires initial mission state")
        if not isinstance(self.clock, FixedTickClock):
            raise TypeError("Glasshouse controlled run requires fixed tick clock")
        if not isinstance(self.policy_bindings, PolicyBindings):
            raise TypeError("Glasshouse controlled run requires policy bindings")
        _validate_policy_sources(self.policy_sources, self.policy_bindings)
        if canonical_command_order(self.commands) != self.commands:
            raise ValueError("Glasshouse controlled run commands must be canonical")
        if not isinstance(self.ticks, int) or isinstance(self.ticks, bool) or self.ticks < 0:
            raise ValueError("Glasshouse controlled run ticks must be non-negative")
        if not isinstance(self.identity, GlasshouseReplayIdentity):
            raise TypeError("Glasshouse controlled run requires replay identity")
        if not isinstance(self.recorded, RecordedReplay):
            raise TypeError("Glasshouse controlled run requires recorded replay")
        if not isinstance(self.trace, CausalTrace):
            raise TypeError("Glasshouse controlled run requires causal trace")
        if not isinstance(self.source_archive, ReplaySourceArchive):
            raise TypeError("Glasshouse controlled run requires source archive")
        replay = self.recorded.replay
        if (
            replay.application_build != self.identity.application_build
            or replay.simulation_version != self.identity.simulation_version
            or replay.mission_hash != self.identity.mission_hash
            or replay.initial_snapshot != capture_authority_snapshot(self.initial_state)
            or replay.commands != self.commands
        ):
            raise ValueError("Glasshouse controlled run replay does not match its baseline")
        if replay.policy_versions != tuple(
            sorted(
                (
                    EntityPolicyVersion(binding.entity_id, binding.policy_version)
                    for binding in self.policy_bindings.entries
                ),
                key=lambda item: item.entity_id.value,
            )
        ):
            raise ValueError("Glasshouse controlled run replay policies do not match bindings")
        if self.recorded.run.state.tick != self.initial_state.tick + self.ticks:
            raise ValueError("Glasshouse controlled run reached an unexpected tick")
        if self.trace.run_state_hash != hash_canonical_state(self.recorded.run.state).digest:
            raise ValueError("Glasshouse controlled run trace does not match replay state")
        if not source_archive_matches_replay(replay, self.source_archive):
            raise ValueError("Glasshouse controlled run source archive does not match replay")


@dataclass(frozen=True, slots=True)
class GlasshouseControlledComparison:
    baseline: GlasshouseControlledRun
    rerun: GlasshouseControlledRun
    comparison: RunComparisonView

    def __post_init__(self) -> None:
        if not isinstance(self.baseline, GlasshouseControlledRun):
            raise TypeError("Glasshouse controlled comparison requires baseline run")
        if not isinstance(self.rerun, GlasshouseControlledRun):
            raise TypeError("Glasshouse controlled comparison requires rerun")
        if not isinstance(self.comparison, RunComparisonView):
            raise TypeError("Glasshouse controlled comparison requires comparison view")


type GlasshouseControlledRerunResult = (
    GlasshouseControlledComparison | GlasshouseRerunUnavailable | GlasshousePolicyFailure
)


def record_glasshouse_execution(
    execution: GlasshouseMissionExecution,
    identity: GlasshouseReplayIdentity,
) -> GlasshouseControlledRun:
    """Record an already-executed Glasshouse run from its exact initial state and commands."""
    if not isinstance(execution, GlasshouseMissionExecution):
        raise TypeError("Glasshouse run recording requires mission execution")
    if not isinstance(identity, GlasshouseReplayIdentity):
        raise TypeError("Glasshouse run recording requires replay identity")
    if execution.queued_commands:
        raise ValueError("Glasshouse run recording requires no queued commands")
    controlled = _controlled_run(
        execution.initial_state,
        execution.clock,
        execution.policy_bindings,
        execution.policy_sources,
        execution.command_log,
        execution.state.tick - execution.initial_state.tick,
        identity,
    )
    if (
        controlled.recorded.run.state != execution.state
        or controlled.recorded.run.events != execution.events
    ):
        raise ValueError("Glasshouse execution cannot be reproduced from recorded inputs")
    return controlled


def controlled_glasshouse_rerun(
    baseline: GlasshouseControlledRun,
    mission: MissionData,
    workbench: GlasshouseWorkbench,
    hostile_sources: tuple[SourceFile, ...],
) -> GlasshouseControlledRerunResult:
    """Rerun only revised policy bindings against the baseline's exact controlled inputs."""
    if not isinstance(baseline, GlasshouseControlledRun):
        raise TypeError("Glasshouse rerun requires a controlled baseline")
    if not isinstance(mission, MissionData):
        raise TypeError("Glasshouse rerun requires mission data")
    if not isinstance(workbench, GlasshouseWorkbench):
        raise TypeError("Glasshouse rerun requires a Glasshouse workbench")
    if not isinstance(hostile_sources, tuple) or any(
        not isinstance(source, SourceFile) for source in hostile_sources
    ):
        raise TypeError("Glasshouse rerun hostile sources must be immutable source files")
    execution = build_glasshouse_mission_execution(mission, workbench, hostile_sources)
    if isinstance(execution, GlasshousePolicyFailure):
        return execution
    if execution.initial_state != baseline.initial_state or execution.clock != baseline.clock:
        return GlasshouseRerunUnavailable(GlasshouseRerunUnavailableCode.INITIAL_STATE_CHANGED)
    rerun = _controlled_run(
        baseline.initial_state,
        baseline.clock,
        execution.policy_bindings,
        execution.policy_sources,
        baseline.commands,
        baseline.ticks,
        baseline.identity,
    )
    return GlasshouseControlledComparison(
        baseline,
        rerun,
        run_comparison_view(baseline.recorded, rerun.recorded, baseline.trace, rerun.trace),
    )


def _controlled_run(
    initial_state: MissionState,
    clock: FixedTickClock,
    policy_bindings: PolicyBindings,
    policy_sources: tuple[SourceFile, ...],
    commands: tuple[ExternalCommand, ...],
    ticks: int,
    identity: GlasshouseReplayIdentity,
) -> GlasshouseControlledRun:
    recorded = record_headless_run(
        initial_state,
        clock,
        ticks,
        application_build=identity.application_build,
        simulation_version=identity.simulation_version,
        mission_hash=identity.mission_hash,
        commands=commands,
        policy_bindings=policy_bindings,
    )
    trace = capture_run_trace(recorded.run, hash_canonical_state(recorded.run.state))
    archive = build_source_archive(
        recorded.replay,
        tuple(
            HistoricalSourceFile(source, _source_language_version(policy_bindings, source))
            for source in policy_sources
        ),
        policy_bindings,
    )
    return GlasshouseControlledRun(
        initial_state,
        clock,
        policy_bindings,
        policy_sources,
        commands,
        ticks,
        identity,
        recorded,
        trace,
        archive,
    )


def _source_language_version(bindings: PolicyBindings, source: SourceFile) -> int:
    for binding in bindings.entries:
        header = binding.artifact.bytecode.header
        if header.source_file_id == source.file_id:
            return header.source_language_version
    raise AssertionError("validated Glasshouse policy sources have no deployed binding")


def _validate_policy_sources(sources: tuple[SourceFile, ...], bindings: PolicyBindings) -> None:
    if not isinstance(sources, tuple) or any(
        not isinstance(source, SourceFile) for source in sources
    ):
        raise TypeError("Glasshouse controlled run sources must be immutable source files")
    source_file_ids = tuple(source.file_id for source in sources)
    if source_file_ids != tuple(sorted(source_file_ids)) or len(set(source_file_ids)) != len(
        source_file_ids
    ):
        raise ValueError("Glasshouse controlled run sources must be unique and source-file ordered")
    binding_file_ids = tuple(
        sorted(binding.artifact.bytecode.header.source_file_id for binding in bindings.entries)
    )
    if source_file_ids != binding_file_ids:
        raise ValueError("Glasshouse controlled run sources must match deployed policy bindings")


def _validate_identifier(value: str, label: str) -> None:
    if (
        not isinstance(value, str)
        or not value
        or not value.isascii()
        or len(value.encode("ascii")) > MAX_REPLAY_TEXT_BYTES
        or any(ord(character) < 33 or ord(character) > 126 for character in value)
    ):
        raise ValueError(f"{label} must be non-empty visible ASCII text")
