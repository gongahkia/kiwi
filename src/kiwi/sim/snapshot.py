"""Immutable authoritative snapshots separate from presentation read models."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.sim.hashing import (
    StateDecodeFailure,
    StateHash,
    decode_canonical_state,
    encode_canonical_state,
    hash_canonical_state_bytes,
)
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.state import MissionState


class SnapshotRestoreCode(StrEnum):
    """Stable failures returned while restoring an authority snapshot."""

    INVALID_PAYLOAD = "SS001_INVALID_PAYLOAD"
    TICK_MISMATCH = "SS002_TICK_MISMATCH"
    HASH_MISMATCH = "SS003_HASH_MISMATCH"


@dataclass(frozen=True, slots=True)
class AuthoritySnapshot:
    """A self-verifying authority payload suitable for replay checkpoint storage."""

    tick: int
    canonical_state: bytes
    state_hash: StateHash

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("snapshot tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("snapshot tick must fit non-negative signed 64-bit range")
        if not isinstance(self.canonical_state, bytes):
            raise ValueError("snapshot canonical state must be bytes")
        if not isinstance(self.state_hash, StateHash):
            raise ValueError("snapshot state hash must be a StateHash")


@dataclass(frozen=True, slots=True)
class SnapshotRestoreFailure:
    """One structured authority-snapshot restoration failure."""

    code: SnapshotRestoreCode
    message: str
    state_failure: StateDecodeFailure | None = None


type SnapshotRestoreResult = MissionState | SnapshotRestoreFailure


def capture_authority_snapshot(state: MissionState) -> AuthoritySnapshot:
    """Capture all materialised authority state without presentation data."""
    payload = encode_canonical_state(state)
    return AuthoritySnapshot(
        tick=state.tick,
        canonical_state=payload,
        state_hash=hash_canonical_state_bytes(payload),
    )


def restore_authority_snapshot(snapshot: AuthoritySnapshot) -> SnapshotRestoreResult:
    """Restore one snapshot after validating its payload, tick, and state hash."""
    if not isinstance(snapshot, AuthoritySnapshot):
        raise TypeError("authority snapshot restoration requires an AuthoritySnapshot")
    state = decode_canonical_state(snapshot.canonical_state)
    if isinstance(state, StateDecodeFailure):
        return SnapshotRestoreFailure(
            SnapshotRestoreCode.INVALID_PAYLOAD,
            "snapshot canonical state is invalid",
            state,
        )
    if snapshot.tick != state.tick:
        return SnapshotRestoreFailure(
            SnapshotRestoreCode.TICK_MISMATCH,
            "snapshot tick does not match its canonical state",
        )
    if hash_canonical_state_bytes(snapshot.canonical_state) != snapshot.state_hash:
        return SnapshotRestoreFailure(
            SnapshotRestoreCode.HASH_MISMATCH,
            "snapshot state hash does not match its canonical state",
        )
    return state
