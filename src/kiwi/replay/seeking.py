"""Versioned replay snapshot sidecars and deterministic checkpoint seeking."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.replay.format import REPLAY_HASH_DIGEST_BYTES, ReplayPacket, hash_replay
from kiwi.sim.clock import FixedTickClock
from kiwi.sim.hashing import MAX_ENCODED_STATE_BYTES, StateHash
from kiwi.sim.policies import EMPTY_POLICY_BINDINGS, PolicyBindings
from kiwi.sim.policy_versions import EntityPolicyVersion
from kiwi.sim.runner import run_headless
from kiwi.sim.snapshot import (
    AuthoritySnapshot,
    SnapshotRestoreFailure,
    restore_authority_snapshot,
)
from kiwi.sim.state import MissionState

SEEK_MAGIC = b"KWI-SEEK\x00"
SEEK_VERSION = 1
MAX_ENCODED_SEEK_INDEX_BYTES = 64 * 1_024 * 1_024
MAX_SEEK_SNAPSHOTS = 65_536


class SeekIndexDecodeFailureCode(StrEnum):
    """Stable failures while decoding an untrusted replay seek sidecar."""

    TOO_LARGE = "SK001_TOO_LARGE"
    INVALID_MAGIC = "SK002_INVALID_MAGIC"
    UNSUPPORTED_VERSION = "SK003_UNSUPPORTED_VERSION"
    INVALID_STRUCTURE = "SK004_INVALID_STRUCTURE"
    TRAILING_BYTES = "SK005_TRAILING_BYTES"


@dataclass(frozen=True, slots=True)
class SeekIndexDecodeFailure:
    """One structured non-throwing seek-sidecar boundary failure."""

    code: SeekIndexDecodeFailureCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, SeekIndexDecodeFailureCode):
            raise ValueError("seek index decode failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("seek index decode failure requires a message")


@dataclass(frozen=True, slots=True)
class ReplaySeekIndex:
    """One replay-hash-bound ascending immutable snapshot index."""

    replay_hash: bytes
    snapshots: tuple[AuthoritySnapshot, ...]

    def __post_init__(self) -> None:
        if (
            not isinstance(self.replay_hash, bytes)
            or len(self.replay_hash) != REPLAY_HASH_DIGEST_BYTES
        ):
            raise ValueError("replay seek index hash must be exactly 32 bytes")
        if not isinstance(self.snapshots, tuple) or not self.snapshots:
            raise ValueError("replay seek index requires an immutable snapshot tuple")
        if len(self.snapshots) > MAX_SEEK_SNAPSHOTS:
            raise ValueError("replay seek index snapshot count exceeds the configured limit")
        previous_tick = -1
        for snapshot in self.snapshots:
            if not isinstance(snapshot, AuthoritySnapshot):
                raise ValueError("replay seek index snapshots must be authority snapshots")
            if snapshot.tick <= previous_tick:
                raise ValueError("replay seek index snapshots must use ascending unique ticks")
            restored = restore_authority_snapshot(snapshot)
            if isinstance(restored, SnapshotRestoreFailure):
                raise ValueError(f"replay seek index snapshot is invalid: {restored.message}")
            previous_tick = snapshot.tick


type SeekIndexDecodeResult = ReplaySeekIndex | SeekIndexDecodeFailure


class ReplaySeekFailureCode(StrEnum):
    """Stable ordinary outcomes while seeking one replay."""

    REPLAY_HASH = "RS001_REPLAY_HASH"
    CHECKPOINTS = "RS002_CHECKPOINTS"
    POLICY_VERSIONS = "RS003_POLICY_VERSIONS"
    TARGET_TICK = "RS004_TARGET_TICK"
    SNAPSHOT = "RS005_SNAPSHOT"


@dataclass(frozen=True, slots=True)
class ReplaySeekFailure:
    """One structured replay-seek failure without a Python traceback."""

    code: ReplaySeekFailureCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, ReplaySeekFailureCode):
            raise ValueError("replay seek failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("replay seek failure requires a message")


@dataclass(frozen=True, slots=True)
class ReplaySeekSuccess:
    """One deterministic target state reconstructed from a checkpoint snapshot."""

    state: MissionState
    snapshot_tick: int

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("replay seek success requires mission state")
        if not isinstance(self.snapshot_tick, int) or isinstance(self.snapshot_tick, bool):
            raise ValueError("replay seek success snapshot tick must be an integer")


type ReplaySeekResult = ReplaySeekSuccess | ReplaySeekFailure


def build_seek_index(
    replay: ReplayPacket,
    snapshots: tuple[AuthoritySnapshot, ...],
) -> ReplaySeekIndex:
    """Bind all recorded checkpoint snapshots to one exact canonical replay packet."""
    if not isinstance(replay, ReplayPacket):
        raise TypeError("seek index construction requires a ReplayPacket")
    index = ReplaySeekIndex(hash_replay(replay), snapshots)
    if not _snapshots_match_checkpoints(replay, index):
        raise ValueError("replay seek snapshots must exactly match replay checkpoints")
    return index


def encode_seek_index(index: ReplaySeekIndex) -> bytes:
    """Encode one validated v1 seek index using a compact deterministic binary layout."""
    if not isinstance(index, ReplaySeekIndex):
        raise TypeError("seek index encoding requires a ReplaySeekIndex")
    chunks = [
        SEEK_MAGIC,
        SEEK_VERSION.to_bytes(2, "big"),
        index.replay_hash,
        len(index.snapshots).to_bytes(4, "big"),
    ]
    for snapshot in index.snapshots:
        chunks.extend(
            (
                snapshot.tick.to_bytes(8, "big"),
                snapshot.state_hash.digest,
                len(snapshot.canonical_state).to_bytes(4, "big"),
                snapshot.canonical_state,
            )
        )
    encoded = b"".join(chunks)
    if len(encoded) > MAX_ENCODED_SEEK_INDEX_BYTES:
        raise ValueError("encoded seek index exceeds the configured byte limit")
    return encoded


def decode_seek_index(data: bytes) -> SeekIndexDecodeResult:
    """Decode and validate a strict v1 replay seek sidecar without authority access."""
    if not isinstance(data, bytes):
        raise TypeError("seek index decoding requires bytes")
    if len(data) > MAX_ENCODED_SEEK_INDEX_BYTES:
        return _decode_failure(
            SeekIndexDecodeFailureCode.TOO_LARGE,
            "seek index exceeds the configured byte limit",
        )
    prefix_length = len(SEEK_MAGIC) + 2
    if len(data) < prefix_length or data[: len(SEEK_MAGIC)] != SEEK_MAGIC:
        return _decode_failure(
            SeekIndexDecodeFailureCode.INVALID_MAGIC, "seek index magic is invalid"
        )
    version = int.from_bytes(data[len(SEEK_MAGIC) : prefix_length], "big")
    if version != SEEK_VERSION:
        return _decode_failure(
            SeekIndexDecodeFailureCode.UNSUPPORTED_VERSION,
            f"unsupported seek index format version {version}",
        )
    reader = _SeekReader(data, prefix_length)
    try:
        replay_hash = reader.read(REPLAY_HASH_DIGEST_BYTES)
        count = reader.read_unsigned(4)
        if count == 0 or count > MAX_SEEK_SNAPSHOTS:
            raise _SeekFormatError("seek index snapshot count is invalid")
        snapshots = tuple(_decode_snapshot(reader) for _ in range(count))
        if reader.remaining:
            return _decode_failure(
                SeekIndexDecodeFailureCode.TRAILING_BYTES,
                "seek index has trailing bytes",
            )
        return ReplaySeekIndex(replay_hash, snapshots)
    except _SeekFormatError as error:
        return _decode_failure(SeekIndexDecodeFailureCode.INVALID_STRUCTURE, error.message)
    except ValueError as error:
        return _decode_failure(SeekIndexDecodeFailureCode.INVALID_STRUCTURE, str(error))


def seek_replay(
    replay: ReplayPacket,
    index: ReplaySeekIndex,
    target_tick: int,
    policy_bindings: PolicyBindings = EMPTY_POLICY_BINDINGS,
) -> ReplaySeekResult:
    """Restore the nearest retained checkpoint then re-execute exactly to one target tick."""
    if not isinstance(replay, ReplayPacket):
        raise TypeError("replay seeking requires a ReplayPacket")
    if not isinstance(index, ReplaySeekIndex):
        raise TypeError("replay seeking requires a ReplaySeekIndex")
    if not isinstance(policy_bindings, PolicyBindings):
        raise TypeError("replay seeking requires policy bindings")
    if index.replay_hash != hash_replay(replay):
        return ReplaySeekFailure(
            ReplaySeekFailureCode.REPLAY_HASH,
            "seek index replay hash does not match replay packet",
        )
    if not _snapshots_match_checkpoints(replay, index):
        return ReplaySeekFailure(
            ReplaySeekFailureCode.CHECKPOINTS,
            "seek index snapshots do not match replay checkpoints",
        )
    actual_policy_versions = tuple(
        EntityPolicyVersion(binding.entity_id, binding.policy_version)
        for binding in policy_bindings.entries
    )
    if actual_policy_versions != replay.policy_versions:
        return ReplaySeekFailure(
            ReplaySeekFailureCode.POLICY_VERSIONS,
            "provided policy bindings do not match replay policy versions",
        )
    if (
        not isinstance(target_tick, int)
        or isinstance(target_tick, bool)
        or not replay.initial_snapshot.tick <= target_tick <= replay.checkpoints[-1].tick
    ):
        return ReplaySeekFailure(
            ReplaySeekFailureCode.TARGET_TICK,
            "replay seek target must fall within the checkpoint timeline",
        )
    snapshot = _nearest_snapshot(index.snapshots, target_tick)
    restored = restore_authority_snapshot(snapshot)
    if isinstance(restored, SnapshotRestoreFailure):
        return ReplaySeekFailure(
            ReplaySeekFailureCode.SNAPSHOT,
            "seek index snapshot cannot be restored",
        )
    commands = tuple(
        command for command in replay.commands if restored.tick <= command.header.tick < target_tick
    )
    run = run_headless(
        restored,
        FixedTickClock(replay.tick_rate),
        target_tick - restored.tick,
        commands,
        policy_bindings=policy_bindings,
    )
    return ReplaySeekSuccess(run.state, snapshot.tick)


def _snapshots_match_checkpoints(replay: ReplayPacket, index: ReplaySeekIndex) -> bool:
    if len(replay.checkpoints) != len(index.snapshots):
        return False
    return all(
        snapshot.tick == checkpoint.tick and snapshot.state_hash == checkpoint.state_hash
        for snapshot, checkpoint in zip(index.snapshots, replay.checkpoints, strict=True)
    )


def _nearest_snapshot(
    snapshots: tuple[AuthoritySnapshot, ...],
    target_tick: int,
) -> AuthoritySnapshot:
    for snapshot in reversed(snapshots):
        if snapshot.tick <= target_tick:
            return snapshot
    raise AssertionError("seek index has no snapshot at or before target tick")


def _decode_snapshot(reader: _SeekReader) -> AuthoritySnapshot:
    try:
        tick = reader.read_unsigned(8)
        state_hash = StateHash(reader.read(32))
        state_size = reader.read_unsigned(4)
        if state_size > MAX_ENCODED_STATE_BYTES:
            raise _SeekFormatError("seek snapshot state exceeds the configured byte limit")
        return AuthoritySnapshot(tick, reader.read(state_size), state_hash)
    except ValueError as error:
        raise _SeekFormatError(str(error)) from error


def _decode_failure(code: SeekIndexDecodeFailureCode, message: str) -> SeekIndexDecodeFailure:
    return SeekIndexDecodeFailure(code, message)


@dataclass(frozen=True, slots=True)
class _SeekFormatError(Exception):
    message: str


@dataclass(slots=True)
class _SeekReader:
    data: bytes
    offset: int

    @property
    def remaining(self) -> int:
        return len(self.data) - self.offset

    def read(self, count: int) -> bytes:
        if count > self.remaining:
            raise _SeekFormatError("seek index is truncated")
        result = self.data[self.offset : self.offset + count]
        self.offset += count
        return result

    def read_unsigned(self, width: int) -> int:
        return int.from_bytes(self.read(width), "big")
