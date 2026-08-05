"""Headless deterministic replay verification."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.replay.format import ReplayPacket
from kiwi.sim.clock import FixedTickClock
from kiwi.sim.hashing import hash_canonical_state
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


@dataclass(frozen=True, slots=True)
class ReplayVerificationFailure:
    """One structured replay verification failure without a Python traceback."""

    code: ReplayVerificationFailureCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, ReplayVerificationFailureCode):
            raise ValueError("replay verification failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("replay verification failure requires a message")


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
) -> ReplayVerificationResult:
    """Re-execute a packet headlessly and validate every recorded checkpoint hash."""
    if not isinstance(replay, ReplayPacket):
        raise TypeError("replay verification requires a ReplayPacket")
    if not isinstance(policy_bindings, PolicyBindings):
        raise TypeError("replay verification requires policy bindings")
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
    for checkpoint in replay.checkpoints[1:]:
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
        if hash_canonical_state(state) != checkpoint.state_hash:
            return ReplayVerificationFailure(
                ReplayVerificationFailureCode.CHECKPOINT_HASH,
                "replay checkpoint hash does not match reconstructed authority state",
            )
    if command_index != len(replay.commands):
        raise AssertionError("replay command lies outside its checkpoint timeline")
    return ReplayVerificationSuccess(state)
