"""Versioned canonical mission-state bytes and stable hashes."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from hashlib import blake2b

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldSubunits
from kiwi.domain.ids import EntityId, IdAllocator, IdKind
from kiwi.sim.randomness import (
    RANDOM_ALGORITHM_VERSION,
    MissionSeed,
    RandomStreams,
    RandomStreamState,
)
from kiwi.sim.scheduled import ScheduledEvent, ScheduledEventKind, ScheduledEventQueue
from kiwi.sim.state import EntityState, MissionPhase, MissionState

CANONICAL_STATE_MAGIC = b"KWI-STATE\x00"
CANONICAL_STATE_VERSION = 1
STATE_HASH_DIGEST_BYTES = 32
MAX_ENCODED_STATE_BYTES = 16 * 1_024 * 1_024
MAX_STATE_COLLECTION_ITEMS = 65_536

_PHASE_PREPARED = 1
_PHASE_ACTIVE = 2
_PHASE_ABORT_REQUESTED = 3
_SCHEDULED_SCENARIO_TRIGGER = 1
_RANDOM_STREAM_COUNT_V1 = 4


class StateDecodeCode(StrEnum):
    """Stable failures returned by the canonical-state decoder."""

    INVALID_MAGIC = "S001_INVALID_MAGIC"
    UNSUPPORTED_VERSION = "S002_UNSUPPORTED_VERSION"
    TOO_LARGE = "S003_TOO_LARGE"
    TRUNCATED = "S004_TRUNCATED"
    INVALID_VALUE = "S005_INVALID_VALUE"
    TRAILING_BYTES = "S006_TRAILING_BYTES"
    INVALID_STATE = "S007_INVALID_STATE"


@dataclass(frozen=True, slots=True)
class StateDecodeFailure:
    """One structured canonical-state decoding failure."""

    code: StateDecodeCode
    offset: int
    message: str


@dataclass(frozen=True, slots=True)
class StateHash:
    """A fixed BLAKE2b-256 digest of canonical mission-state bytes."""

    digest: bytes

    def __post_init__(self) -> None:
        if not isinstance(self.digest, bytes):
            raise ValueError("state hash digest must be bytes")
        if len(self.digest) != STATE_HASH_DIGEST_BYTES:
            raise ValueError("state hash digest must be exactly 32 bytes")

    @property
    def hex(self) -> str:
        """Render the digest for CLI, test, and replay diagnostics."""
        return self.digest.hex()


type StateDecodeResult = MissionState | StateDecodeFailure


def encode_canonical_state(state: MissionState) -> bytes:
    """Encode one validated mission state in canonical binary version 1 form."""
    if not isinstance(state, MissionState):
        raise TypeError("canonical state encoding requires mission state")
    writer = _Writer()
    writer.write(CANONICAL_STATE_MAGIC)
    writer.u16(CANONICAL_STATE_VERSION, "canonical state version")
    writer.u64(state.tick, "mission tick")
    writer.u8(_encode_phase(state.phase), "mission phase")
    writer.items(len(state.entities), "entity count")
    for entity in state.entities:
        writer.i64(entity.entity_id.value, "entity ID")
        writer.i64(entity.position.x.value, "entity x")
        writer.i64(entity.position.y.value, "entity y")
        writer.u64(entity.position.elevation.value, "entity elevation")
    for next_id in state.id_allocator.next_ids:
        writer.u64(next_id, "ID allocator counter")
    _encode_scheduled_events(writer, state.scheduled_events)
    _encode_random_streams(writer, state.random_streams)
    encoded = bytes(writer.data)
    if len(encoded) > MAX_ENCODED_STATE_BYTES:
        raise ValueError("canonical state exceeds the configured byte limit")
    return encoded


def decode_canonical_state(data: bytes) -> StateDecodeResult:
    """Decode one bounded state payload without accepting noncanonical values."""
    if not isinstance(data, bytes):
        raise TypeError("canonical state data must be bytes")
    if len(data) > MAX_ENCODED_STATE_BYTES:
        return StateDecodeFailure(
            StateDecodeCode.TOO_LARGE,
            0,
            "canonical state exceeds the configured byte limit",
        )
    if len(data) < len(CANONICAL_STATE_MAGIC) or not data.startswith(CANONICAL_STATE_MAGIC):
        return StateDecodeFailure(
            StateDecodeCode.INVALID_MAGIC,
            0,
            "canonical state format identifier is invalid",
        )
    reader = _Reader(data, len(CANONICAL_STATE_MAGIC))
    try:
        version = reader.u16()
        if version != CANONICAL_STATE_VERSION:
            raise _DecodeError(
                StateDecodeCode.UNSUPPORTED_VERSION,
                reader.offset - 2,
                f"unsupported canonical state version {version}",
            )
        state = _decode_state(reader)
        if reader.remaining:
            raise _DecodeError(
                StateDecodeCode.TRAILING_BYTES,
                reader.offset,
                "canonical state contains trailing bytes",
            )
    except _DecodeError as error:
        return StateDecodeFailure(error.code, error.offset, error.message)
    except (TypeError, ValueError):
        return StateDecodeFailure(
            StateDecodeCode.INVALID_STATE,
            reader.offset,
            "canonical state fields do not form a valid mission state",
        )
    return state


def hash_canonical_state(state: MissionState) -> StateHash:
    """Hash canonical state bytes with the fixed BLAKE2b-256 digest policy."""
    return hash_canonical_state_bytes(encode_canonical_state(state))


def hash_canonical_state_bytes(data: bytes) -> StateHash:
    """Hash bytes already produced by the canonical mission-state encoder."""
    if not isinstance(data, bytes):
        raise TypeError("canonical state bytes must be bytes")
    return StateHash(blake2b(data, digest_size=STATE_HASH_DIGEST_BYTES).digest())


def _encode_scheduled_events(writer: _Writer, queue: ScheduledEventQueue) -> None:
    writer.u64(queue.next_sequence, "scheduled queue next sequence")
    writer.items(len(queue.pending), "scheduled event count")
    for event in queue.pending:
        writer.u64(event.tick, "scheduled event tick")
        writer.u64(event.sequence, "scheduled event sequence")
        writer.u8(_encode_scheduled_kind(event.kind), "scheduled event kind")


def _encode_random_streams(writer: _Writer, streams: RandomStreams) -> None:
    if len(streams.states) != _RANDOM_STREAM_COUNT_V1:
        raise ValueError("state format version 1 requires exactly four random streams")
    writer.u16(RANDOM_ALGORITHM_VERSION, "random algorithm version")
    writer.u64(streams.seed.value, "mission seed")
    for stream in streams.states:
        writer.u64(stream.state, "random stream state")
        writer.u64(stream.next_draw_index, "random stream draw index")


def _decode_state(reader: _Reader) -> MissionState:
    tick = reader.u64()
    phase = _decode_phase(reader.u8(), reader.offset - 1)
    entity_count = reader.items("entity count")
    entities = tuple(_decode_entity(reader) for _ in range(entity_count))
    id_allocator = IdAllocator(tuple(reader.u64() for _ in IdKind))
    scheduled_events = _decode_scheduled_events(reader)
    random_streams = _decode_random_streams(reader)
    return MissionState(
        tick=tick,
        phase=phase,
        entities=entities,
        id_allocator=id_allocator,
        scheduled_events=scheduled_events,
        random_streams=random_streams,
    )


def _decode_entity(reader: _Reader) -> EntityState:
    return EntityState(
        entity_id=EntityId(reader.i64()),
        position=WorldPosition(
            x=WorldSubunits(reader.i64()),
            y=WorldSubunits(reader.i64()),
            elevation=ElevationLayer(reader.u64()),
        ),
    )


def _decode_scheduled_events(reader: _Reader) -> ScheduledEventQueue:
    next_sequence = reader.u64()
    count = reader.items("scheduled event count")
    pending = tuple(
        ScheduledEvent(
            tick=reader.u64(),
            sequence=reader.u64(),
            kind=_decode_scheduled_kind(reader.u8(), reader.offset - 1),
        )
        for _ in range(count)
    )
    return ScheduledEventQueue(pending=pending, next_sequence=next_sequence)


def _decode_random_streams(reader: _Reader) -> RandomStreams:
    algorithm_version = reader.u16()
    if algorithm_version != RANDOM_ALGORITHM_VERSION:
        raise _DecodeError(
            StateDecodeCode.INVALID_VALUE,
            reader.offset - 2,
            f"unsupported random algorithm version {algorithm_version}",
        )
    seed = MissionSeed(reader.u64())
    states = tuple(
        RandomStreamState(reader.u64(), reader.u64()) for _ in range(_RANDOM_STREAM_COUNT_V1)
    )
    return RandomStreams(seed=seed, states=states)


def _encode_phase(phase: MissionPhase) -> int:
    if phase is MissionPhase.PREPARED:
        return _PHASE_PREPARED
    if phase is MissionPhase.ACTIVE:
        return _PHASE_ACTIVE
    if phase is MissionPhase.ABORT_REQUESTED:
        return _PHASE_ABORT_REQUESTED
    raise TypeError("mission phase is unsupported")


def _decode_phase(tag: int, offset: int) -> MissionPhase:
    if tag == _PHASE_PREPARED:
        return MissionPhase.PREPARED
    if tag == _PHASE_ACTIVE:
        return MissionPhase.ACTIVE
    if tag == _PHASE_ABORT_REQUESTED:
        return MissionPhase.ABORT_REQUESTED
    raise _DecodeError(StateDecodeCode.INVALID_VALUE, offset, f"invalid mission phase tag {tag}")


def _encode_scheduled_kind(kind: ScheduledEventKind) -> int:
    if kind is ScheduledEventKind.SCENARIO_TRIGGER:
        return _SCHEDULED_SCENARIO_TRIGGER
    raise TypeError("scheduled event kind is unsupported")


def _decode_scheduled_kind(tag: int, offset: int) -> ScheduledEventKind:
    if tag == _SCHEDULED_SCENARIO_TRIGGER:
        return ScheduledEventKind.SCENARIO_TRIGGER
    raise _DecodeError(
        StateDecodeCode.INVALID_VALUE, offset, f"invalid scheduled event kind tag {tag}"
    )


class _Writer:
    def __init__(self) -> None:
        self.data = bytearray()

    def write(self, value: bytes) -> None:
        self.data.extend(value)

    def u8(self, value: int, name: str) -> None:
        self.data.append(self._bounded(value, 0, (1 << 8) - 1, name))

    def u16(self, value: int, name: str) -> None:
        self.write(self._bounded(value, 0, (1 << 16) - 1, name).to_bytes(2, "big"))

    def u32(self, value: int, name: str) -> None:
        self.write(self._bounded(value, 0, (1 << 32) - 1, name).to_bytes(4, "big"))

    def u64(self, value: int, name: str) -> None:
        self.write(self._bounded(value, 0, (1 << 64) - 1, name).to_bytes(8, "big"))

    def i64(self, value: int, name: str) -> None:
        self.write(
            self._bounded(value, -(1 << 63), (1 << 63) - 1, name).to_bytes(8, "big", signed=True)
        )

    def items(self, value: int, name: str) -> None:
        if value > MAX_STATE_COLLECTION_ITEMS:
            raise ValueError(f"{name} exceeds the configured item limit")
        self.u32(value, name)

    @staticmethod
    def _bounded(value: int, lower: int, upper: int, name: str) -> int:
        if not isinstance(value, int) or isinstance(value, bool):
            raise TypeError(f"{name} must be an integer")
        if not lower <= value <= upper:
            raise ValueError(f"{name} is out of range")
        return value


class _Reader:
    def __init__(self, data: bytes, offset: int) -> None:
        self.data = data
        self.offset = offset

    @property
    def remaining(self) -> int:
        return len(self.data) - self.offset

    def u8(self) -> int:
        return self._read_int(1)

    def u16(self) -> int:
        return self._read_int(2)

    def u32(self) -> int:
        return self._read_int(4)

    def u64(self) -> int:
        return self._read_int(8)

    def i64(self) -> int:
        data = self.read(8)
        return int.from_bytes(data, "big", signed=True)

    def items(self, name: str) -> int:
        value = self.u32()
        if value > MAX_STATE_COLLECTION_ITEMS:
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                self.offset - 4,
                f"{name} exceeds the configured item limit",
            )
        return value

    def read(self, count: int) -> bytes:
        if self.remaining < count:
            raise _DecodeError(
                StateDecodeCode.TRUNCATED,
                self.offset,
                "canonical state ends before a complete value",
            )
        data = self.data[self.offset : self.offset + count]
        self.offset += count
        return data

    def _read_int(self, count: int) -> int:
        return int.from_bytes(self.read(count), "big")


@dataclass(frozen=True, slots=True)
class _DecodeError(Exception):
    code: StateDecodeCode
    offset: int
    message: str
