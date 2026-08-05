"""Headless deterministic replay verification."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.replay.format import ReplayPacket
from kiwi.replay.seeking import ReplaySeekIndex, seek_index_matches_replay
from kiwi.sim.clock import FixedTickClock
from kiwi.sim.determinism import CanonicalStateDifference, first_canonical_state_difference
from kiwi.sim.hashing import StateHash, hash_canonical_state
from kiwi.sim.policies import EMPTY_POLICY_BINDINGS, PolicyBindings
from kiwi.sim.policy_versions import EntityPolicyVersion
from kiwi.sim.runner import run_headless
from kiwi.sim.snapshot import SnapshotRestoreFailure, restore_authority_snapshot
from kiwi.sim.state import MissionState


class ReplayVerificationFailureCode(StrEnum):
    """Stable ordinary outcomes of replay verification."""

    INITIAL_SNAPSHOT = "RV001_INITIAL_SNAPSHOT"
    POLICY_VERSIONS = "RV002_POLICY_VERSIONS"
    CHECKPOINT_HASH = "RV003_CHECKPOINT_HASH"
    SEEK_INDEX = "RV004_SEEK_INDEX"


@dataclass(frozen=True, slots=True)
class ReplayCheckpointDivergence:
    """The first recorded checkpoint whose reconstructed state hash differs."""

    checkpoint_index: int
    tick: int
    expected_hash: StateHash
    actual_hash: StateHash
    difference: CanonicalStateDifference | None = None

    def __post_init__(self) -> None:
        if (
            not isinstance(self.checkpoint_index, int)
            or isinstance(self.checkpoint_index, bool)
            or self.checkpoint_index <= 0
        ):
            raise ValueError("replay divergence checkpoint index must be positive")
        if not isinstance(self.tick, int) or isinstance(self.tick, bool) or self.tick < 0:
            raise ValueError("replay divergence tick must be a non-negative integer")
        if not isinstance(self.expected_hash, StateHash) or not isinstance(
            self.actual_hash, StateHash
        ):
            raise ValueError("replay divergence hashes must be StateHash values")
        if self.difference is not None and not isinstance(self.difference, CanonicalStateDifference):
            raise ValueError("replay divergence difference must be canonical state difference")


@dataclass(frozen=True, slots=True)
class ReplayVerificationFailure:
    """One structured replay verification failure without a Python traceback."""

    code: ReplayVerificationFailureCode
    message: str
    divergence: ReplayCheckpointDivergence | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.code, ReplayVerificationFailureCode):
            raise ValueError("replay verification failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("replay verification failure requires a message")
        if self.code is ReplayVerificationFailureCode.CHECKPOINT_HASH:
            if not isinstance(self.divergence, ReplayCheckpointDivergence):
                raise ValueError("checkpoint hash failure requires a replay divergence")
        elif self.divergence is not None:
            raise ValueError("only checkpoint hash failures may retain a replay divergence")


@dataclass(frozen=True, slots=True)
class ReplayVerificationSuccess:
    """One verified replay and its final reconstructed authority state."""

    state: MissionState

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("replay verification success requires mission state")


type ReplayVerificationResult = ReplayVerificationSuccess | ReplayVerificationFailure


def verify_replay(
    replay: ReplayPacket,
    policy_bindings: PolicyBindings = EMPTY_POLICY_BINDINGS,
    *,
    seek_index: ReplaySeekIndex | None = None,
) -> ReplayVerificationResult:
    """Re-execute a packet headlessly and validate every recorded checkpoint hash."""
    if not isinstance(replay, ReplayPacket):
        raise TypeError("replay verification requires a ReplayPacket")
    if not isinstance(policy_bindings, PolicyBindings):
        raise TypeError("replay verification requires policy bindings")
    if seek_index is not None and not isinstance(seek_index, ReplaySeekIndex):
        raise TypeError("replay verification seek index must be a ReplaySeekIndex or None")
    if seek_index is not None and not seek_index_matches_replay(replay, seek_index):
        return ReplayVerificationFailure(
            ReplayVerificationFailureCode.SEEK_INDEX,
            "replay verification seek index does not match the replay packet",
        )
    actual_policy_versions = tuple(
        EntityPolicyVersion(binding.entity_id, binding.policy_version)
        for binding in policy_bindings.entries
    )
    if actual_policy_versions != replay.policy_versions:
        return ReplayVerificationFailure(
            ReplayVerificationFailureCode.POLICY_VERSIONS,
            "provided policy bindings do not match replay policy versions",
        )
    restored = restore_authority_snapshot(replay.initial_snapshot)
    if isinstance(restored, SnapshotRestoreFailure):
        return ReplayVerificationFailure(
            ReplayVerificationFailureCode.INITIAL_SNAPSHOT,
            "replay initial snapshot cannot be restored",
        )
    clock = FixedTickClock(replay.tick_rate)
    state = restored
    command_index = 0
    for checkpoint_index, checkpoint in enumerate(replay.checkpoints[1:], start=1):
        segment_commands = []
        while (
            command_index < len(replay.commands)
            and replay.commands[command_index].header.tick < checkpoint.tick
        ):
            segment_commands.append(replay.commands[command_index])
            command_index += 1
        run = run_headless(
            state,
            clock,
            checkpoint.tick - state.tick,
            tuple(segment_commands),
            policy_bindings=policy_bindings,
        )
        state = run.state
        actual_hash = hash_canonical_state(state)
        if actual_hash != checkpoint.state_hash:
            return ReplayVerificationFailure(
                ReplayVerificationFailureCode.CHECKPOINT_HASH,
                "replay checkpoint hash does not match reconstructed authority state",
                ReplayCheckpointDivergence(
                    checkpoint_index,
                    checkpoint.tick,
                    checkpoint.state_hash,
                    actual_hash,
                    _canonical_difference(seek_index, checkpoint_index, state),
                ),
            )
    if command_index != len(replay.commands):
        raise AssertionError("replay command lies outside its checkpoint timeline")
    return ReplayVerificationSuccess(state)


def _canonical_difference(
    seek_index: ReplaySeekIndex | None,
    checkpoint_index: int,
    actual_state: MissionState,
) -> CanonicalStateDifference | None:
    if seek_index is None:
        return None
    restored = restore_authority_snapshot(seek_index.snapshots[checkpoint_index])
    if isinstance(restored, SnapshotRestoreFailure):
        raise AssertionError("validated replay seek index snapshot cannot fail restoration")
    difference = first_canonical_state_difference(restored, actual_state)
    if difference is None:
        raise AssertionError("distinct checkpoint hashes require a canonical state difference")
    return difference
