"""Canonical version-one replay packet codec."""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EntityId
from kiwi.sim.clock import TickRate
from kiwi.sim.commands import (
    CommandHeader,
    CommandSource,
    ExternalCommand,
    IssueSignal,
    RequestAbort,
    SignalName,
    StartMission,
    canonical_command_order,
)
from kiwi.sim.hashing import STATE_HASH_DIGEST_BYTES, StateHash
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.policy_versions import EntityPolicyVersion, PolicyVersion, PolicyVersionStore
from kiwi.sim.randomness import MissionSeed
from kiwi.sim.snapshot import (
    AuthoritySnapshot,
    SnapshotRestoreFailure,
    restore_authority_snapshot,
)

REPLAY_MAGIC = b"KWI-RUN\x00"
REPLAY_VERSION = 1
MAX_ENCODED_REPLAY_BYTES = 64 * 1_024 * 1_024
MAX_REPLAY_COMMANDS = 65_536
MAX_REPLAY_CHECKPOINTS = 65_536
MAX_REPLAY_TEXT_BYTES = 256


class ReplayDecodeFailureCode(StrEnum):
    """Stable failures while decoding an untrusted replay packet."""

    TOO_LARGE = "RP001_TOO_LARGE"
    INVALID_MAGIC = "RP002_INVALID_MAGIC"
    UNSUPPORTED_VERSION = "RP003_UNSUPPORTED_VERSION"
    INVALID_JSON = "RP004_INVALID_JSON"
    INVALID_STRUCTURE = "RP005_INVALID_STRUCTURE"
    NONCANONICAL = "RP006_NONCANONICAL"


@dataclass(frozen=True, slots=True)
class ReplayDecodeFailure:
    """One structured non-throwing replay-file boundary failure."""

    code: ReplayDecodeFailureCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, ReplayDecodeFailureCode):
            raise ValueError("replay decode failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("replay decode failure requires a message")


@dataclass(frozen=True, slots=True)
class ReplayCheckpoint:
    """One authoritative state-hash checkpoint in a replay timeline."""

    tick: int
    state_hash: StateHash

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("replay checkpoint tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("replay checkpoint tick must fit non-negative signed 64-bit range")
        if not isinstance(self.state_hash, StateHash):
            raise ValueError("replay checkpoint hash must be a StateHash")


@dataclass(frozen=True, slots=True)
class ReplayPacket:
    """Complete version-one input and checkpoint manifest for one headless run."""

    application_build: str
    simulation_version: str
    mission_hash: bytes
    policy_versions: tuple[EntityPolicyVersion, ...]
    initial_snapshot: AuthoritySnapshot
    seed: MissionSeed
    tick_rate: TickRate
    commands: tuple[ExternalCommand, ...]
    checkpoints: tuple[ReplayCheckpoint, ...]

    def __post_init__(self) -> None:
        _require_identifier(self.application_build, "application build")
        _require_identifier(self.simulation_version, "simulation version")
        _require_digest(self.mission_hash, "mission hash")
        if not isinstance(self.policy_versions, tuple):
            raise ValueError("replay policy versions must be an immutable tuple")
        PolicyVersionStore(self.policy_versions)
        if not isinstance(self.initial_snapshot, AuthoritySnapshot):
            raise ValueError("replay initial snapshot must be an AuthoritySnapshot")
        restored = restore_authority_snapshot(self.initial_snapshot)
        if isinstance(restored, SnapshotRestoreFailure):
            raise ValueError(f"replay initial snapshot is invalid: {restored.message}")
        if not isinstance(self.seed, MissionSeed):
            raise ValueError("replay seed must be a MissionSeed")
        if restored.random_streams.seed != self.seed:
            raise ValueError("replay seed must match the initial snapshot")
        entity_ids = tuple(entity.entity_id for entity in restored.entities)
        if any(version.entity_id not in entity_ids for version in self.policy_versions):
            raise ValueError("replay policy versions must belong to initial snapshot entities")
        if not isinstance(self.tick_rate, TickRate):
            raise ValueError("replay tick rate must be a TickRate")
        if not isinstance(self.commands, tuple):
            raise ValueError("replay commands must be an immutable tuple")
        if len(self.commands) > MAX_REPLAY_COMMANDS:
            raise ValueError("replay command count exceeds the configured limit")
        if canonical_command_order(self.commands) != self.commands:
            raise ValueError("replay commands must use canonical command order")
        if any(command.header.tick < self.initial_snapshot.tick for command in self.commands):
            raise ValueError("replay commands cannot precede the initial snapshot")
        if not isinstance(self.checkpoints, tuple):
            raise ValueError("replay checkpoints must be an immutable tuple")
        if not self.checkpoints:
            raise ValueError("replay requires an initial checkpoint")
        if len(self.checkpoints) > MAX_REPLAY_CHECKPOINTS:
            raise ValueError("replay checkpoint count exceeds the configured limit")
        expected_initial = ReplayCheckpoint(
            self.initial_snapshot.tick,
            self.initial_snapshot.state_hash,
        )
        if self.checkpoints[0] != expected_initial:
            raise ValueError("replay first checkpoint must match the initial snapshot")
        previous_tick = -1
        for checkpoint in self.checkpoints:
            if not isinstance(checkpoint, ReplayCheckpoint):
                raise ValueError("replay checkpoints must contain replay checkpoints")
            if checkpoint.tick <= previous_tick:
                raise ValueError("replay checkpoints must use ascending unique ticks")
            previous_tick = checkpoint.tick


type ReplayDecodeResult = ReplayPacket | ReplayDecodeFailure


def encode_replay(replay: ReplayPacket) -> bytes:
    """Encode one validated replay into canonical version-one packet bytes."""
    if not isinstance(replay, ReplayPacket):
        raise TypeError("replay encoding requires a ReplayPacket")
    payload = json.dumps(
        _packet_object(replay),
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    encoded = REPLAY_MAGIC + REPLAY_VERSION.to_bytes(2, "big") + payload
    if len(encoded) > MAX_ENCODED_REPLAY_BYTES:
        raise ValueError("encoded replay exceeds the configured byte limit")
    return encoded


def decode_replay(data: bytes) -> ReplayDecodeResult:
    """Decode and validate canonical version-one replay bytes headlessly."""
    if not isinstance(data, bytes):
        raise TypeError("replay decoding requires bytes")
    if len(data) > MAX_ENCODED_REPLAY_BYTES:
        return _failure(
            ReplayDecodeFailureCode.TOO_LARGE, "replay exceeds the configured byte limit"
        )
    prefix_length = len(REPLAY_MAGIC) + 2
    if len(data) < prefix_length or data[: len(REPLAY_MAGIC)] != REPLAY_MAGIC:
        return _failure(ReplayDecodeFailureCode.INVALID_MAGIC, "replay packet magic is invalid")
    version = int.from_bytes(data[len(REPLAY_MAGIC) : prefix_length], "big")
    if version != REPLAY_VERSION:
        return _failure(
            ReplayDecodeFailureCode.UNSUPPORTED_VERSION,
            f"unsupported replay format version {version}",
        )
    try:
        payload = json.loads(data[prefix_length:].decode("utf-8"), object_pairs_hook=_unique_object)
    except UnicodeDecodeError:
        return _failure(ReplayDecodeFailureCode.INVALID_JSON, "replay payload is not valid UTF-8")
    except json.JSONDecodeError:
        return _failure(ReplayDecodeFailureCode.INVALID_JSON, "replay payload is not valid JSON")
    except _DuplicateFieldError:
        return _failure(
            ReplayDecodeFailureCode.INVALID_STRUCTURE, "replay payload has duplicate fields"
        )
    try:
        replay = _parse_packet(payload)
    except _ReplayFormatError as error:
        return _failure(ReplayDecodeFailureCode.INVALID_STRUCTURE, error.message)
    if encode_replay(replay) != data:
        return _failure(
            ReplayDecodeFailureCode.NONCANONICAL,
            "replay packet is not canonically encoded",
        )
    return replay


def _packet_object(replay: ReplayPacket) -> dict[str, object]:
    return {
        "application_build": replay.application_build,
        "checkpoints": [_checkpoint_object(checkpoint) for checkpoint in replay.checkpoints],
        "commands": [_command_object(command) for command in replay.commands],
        "initial_snapshot": _snapshot_object(replay.initial_snapshot),
        "mission_hash": replay.mission_hash.hex(),
        "policy_versions": [_policy_object(version) for version in replay.policy_versions],
        "seed": replay.seed.value,
        "simulation_version": replay.simulation_version,
        "tick_rate": int(replay.tick_rate),
    }


def _checkpoint_object(checkpoint: ReplayCheckpoint) -> dict[str, object]:
    return {"state_hash": checkpoint.state_hash.digest.hex(), "tick": checkpoint.tick}


def _command_object(command: ExternalCommand) -> dict[str, object]:
    header = command.header
    base: dict[str, object] = {
        "sequence": header.sequence,
        "source": header.source.value,
        "tick": header.tick,
    }
    if isinstance(command, StartMission):
        return base | {"kind": "start_mission"}
    if isinstance(command, RequestAbort):
        return base | {"kind": "request_abort"}
    if isinstance(command, IssueSignal):
        return base | {
            "kind": "issue_signal",
            "signal": command.signal.value,
            "target": None if command.target is None else command.target.value,
        }
    raise AssertionError("unsupported external command")


def _snapshot_object(snapshot: AuthoritySnapshot) -> dict[str, object]:
    return {
        "canonical_state": snapshot.canonical_state.hex(),
        "state_hash": snapshot.state_hash.digest.hex(),
        "tick": snapshot.tick,
    }


def _policy_object(version: EntityPolicyVersion) -> dict[str, object]:
    return {"entity_id": version.entity_id.value, "policy_hash": version.version.digest.hex()}


def _parse_packet(value: object) -> ReplayPacket:
    packet = _mapping(value, "replay")
    _fields(
        packet,
        {
            "application_build",
            "checkpoints",
            "commands",
            "initial_snapshot",
            "mission_hash",
            "policy_versions",
            "seed",
            "simulation_version",
            "tick_rate",
        },
        "replay",
    )
    commands = _list(packet["commands"], "replay commands")
    checkpoints = _list(packet["checkpoints"], "replay checkpoints")
    policy_versions = _list(packet["policy_versions"], "replay policy versions")
    if len(commands) > MAX_REPLAY_COMMANDS:
        raise _ReplayFormatError("replay command count exceeds the configured limit")
    if len(checkpoints) > MAX_REPLAY_CHECKPOINTS:
        raise _ReplayFormatError("replay checkpoint count exceeds the configured limit")
    try:
        return ReplayPacket(
            application_build=_identifier(packet["application_build"], "application build"),
            simulation_version=_identifier(packet["simulation_version"], "simulation version"),
            mission_hash=_digest(packet["mission_hash"], "mission hash"),
            policy_versions=tuple(_parse_policy(item) for item in policy_versions),
            initial_snapshot=_parse_snapshot(packet["initial_snapshot"]),
            seed=MissionSeed(_integer(packet["seed"], "replay seed")),
            tick_rate=TickRate(_integer(packet["tick_rate"], "replay tick rate")),
            commands=tuple(_parse_command(item) for item in commands),
            checkpoints=tuple(_parse_checkpoint(item) for item in checkpoints),
        )
    except (TypeError, ValueError) as error:
        raise _ReplayFormatError(str(error)) from error


def _parse_checkpoint(value: object) -> ReplayCheckpoint:
    checkpoint = _mapping(value, "replay checkpoint")
    _fields(checkpoint, {"state_hash", "tick"}, "replay checkpoint")
    try:
        return ReplayCheckpoint(
            _integer(checkpoint["tick"], "replay checkpoint tick"),
            StateHash(_digest(checkpoint["state_hash"], "replay checkpoint")),
        )
    except (TypeError, ValueError) as error:
        raise _ReplayFormatError(str(error)) from error


def _parse_command(value: object) -> ExternalCommand:
    command = _mapping(value, "replay command")
    kind = _text(command.get("kind"), "replay command kind")
    try:
        if kind == "start_mission":
            _fields(command, {"kind", "sequence", "source", "tick"}, "start mission command")
            return StartMission(_parse_header(command))
        if kind == "request_abort":
            _fields(command, {"kind", "sequence", "source", "tick"}, "abort command")
            return RequestAbort(_parse_header(command))
        if kind == "issue_signal":
            _fields(
                command,
                {"kind", "sequence", "signal", "source", "target", "tick"},
                "signal command",
            )
            target_value = command["target"]
            target = (
                None
                if target_value is None
                else EntityId(_integer(target_value, "signal command target"))
            )
            return IssueSignal(
                _parse_header(command),
                SignalName(_text(command["signal"], "signal command name")),
                target,
            )
    except (TypeError, ValueError) as error:
        raise _ReplayFormatError(str(error)) from error
    raise _ReplayFormatError("replay command kind is unsupported")


def _parse_header(value: dict[str, object]) -> CommandHeader:
    return CommandHeader(
        tick=_integer(value["tick"], "replay command tick"),
        sequence=_integer(value["sequence"], "replay command sequence"),
        source=CommandSource(_text(value["source"], "replay command source")),
    )


def _parse_snapshot(value: object) -> AuthoritySnapshot:
    snapshot = _mapping(value, "replay initial snapshot")
    _fields(snapshot, {"canonical_state", "state_hash", "tick"}, "replay initial snapshot")
    try:
        return AuthoritySnapshot(
            _integer(snapshot["tick"], "replay initial snapshot tick"),
            _bytes(snapshot["canonical_state"], "replay initial snapshot state"),
            StateHash(_digest(snapshot["state_hash"], "replay initial snapshot")),
        )
    except (TypeError, ValueError) as error:
        raise _ReplayFormatError(str(error)) from error


def _parse_policy(value: object) -> EntityPolicyVersion:
    policy = _mapping(value, "replay policy version")
    _fields(policy, {"entity_id", "policy_hash"}, "replay policy version")
    try:
        return EntityPolicyVersion(
            EntityId(_integer(policy["entity_id"], "replay policy entity ID")),
            PolicyVersion(_digest(policy["policy_hash"], "replay policy")),
        )
    except (TypeError, ValueError) as error:
        raise _ReplayFormatError(str(error)) from error


def _mapping(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise _ReplayFormatError(f"{label} must be an object")
    return value


def _fields(value: dict[str, object], expected: set[str], label: str) -> None:
    if set(value) != expected:
        raise _ReplayFormatError(f"{label} fields are invalid")


def _list(value: object, label: str) -> list[object]:
    if not isinstance(value, list):
        raise _ReplayFormatError(f"{label} must be an array")
    return value


def _integer(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise _ReplayFormatError(f"{label} must be an integer")
    return value


def _text(value: object, label: str) -> str:
    if not isinstance(value, str):
        raise _ReplayFormatError(f"{label} must be text")
    return value


def _identifier(value: object, label: str) -> str:
    text = _text(value, label)
    try:
        _require_identifier(text, label)
    except ValueError as error:
        raise _ReplayFormatError(str(error)) from error
    return text


def _require_identifier(value: object, label: str) -> None:
    if not isinstance(value, str) or not value or not value.isascii():
        raise ValueError(f"{label} must be non-empty ASCII text")
    if len(value.encode("ascii")) > MAX_REPLAY_TEXT_BYTES:
        raise ValueError(f"{label} exceeds the configured byte limit")
    if any(ord(character) < 33 or ord(character) > 126 for character in value):
        raise ValueError(f"{label} must use visible ASCII characters")


def _digest(value: object, label: str) -> bytes:
    text = _text(value, f"{label} hash")
    try:
        digest = bytes.fromhex(text)
    except ValueError as error:
        raise _ReplayFormatError(f"{label} hash is not hexadecimal") from error
    if len(digest) != STATE_HASH_DIGEST_BYTES or text != digest.hex():
        raise _ReplayFormatError(f"{label} hash is invalid")
    return digest


def _require_digest(value: object, label: str) -> None:
    if not isinstance(value, bytes) or len(value) != STATE_HASH_DIGEST_BYTES:
        raise ValueError(f"{label} must be exactly 32 bytes")


def _bytes(value: object, label: str) -> bytes:
    text = _text(value, label)
    try:
        result = bytes.fromhex(text)
    except ValueError as error:
        raise _ReplayFormatError(f"{label} is not hexadecimal") from error
    if text != result.hex():
        raise _ReplayFormatError(f"{label} is invalid")
    return result


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, item in pairs:
        if key in value:
            raise _DuplicateFieldError()
        value[key] = item
    return value


def _failure(code: ReplayDecodeFailureCode, message: str) -> ReplayDecodeFailure:
    return ReplayDecodeFailure(code, message)


@dataclass(frozen=True, slots=True)
class _ReplayFormatError(Exception):
    message: str


@dataclass(frozen=True, slots=True)
class _DuplicateFieldError(Exception):
    pass
