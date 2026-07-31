"""Versioned canonical mission-state bytes and stable hashes."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from hashlib import blake2b

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import EntityId, EventId, IdAllocator, IdKind, ObstacleId
from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.runtime_values import (
    MAX_RUNTIME_STRING_BYTES,
    BooleanValue,
    IntegerValue,
    ListValue,
    OptionNoneValue,
    OptionSomeValue,
    QuantityValue,
    RecordValue,
    RuntimeValue,
    StringValue,
    UnitValue,
)
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.memory import (
    MAX_POLICY_MEMORY_DEPTH,
    EntityPolicyMemory,
    PolicyMemoryStore,
    is_persistable_memory_value,
)
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.policy_versions import (
    POLICY_VERSION_DIGEST_BYTES,
    EntityPolicyVersion,
    PolicyVersion,
    PolicyVersionStore,
)
from kiwi.sim.randomness import (
    RANDOM_ALGORITHM_VERSION,
    MissionSeed,
    RandomStreams,
    RandomStreamState,
)
from kiwi.sim.scheduled import ScheduledEvent, ScheduledEventKind, ScheduledEventQueue
from kiwi.sim.state import EntityState, MissionPhase, MissionState, MovementAction

CANONICAL_STATE_MAGIC = b"KWI-STATE\x00"
CANONICAL_STATE_VERSION = 6
STATE_HASH_DIGEST_BYTES = 32
MAX_ENCODED_STATE_BYTES = 16 * 1_024 * 1_024
MAX_STATE_COLLECTION_ITEMS = 65_536

_PHASE_PREPARED = 1
_PHASE_ACTIVE = 2
_PHASE_ABORT_REQUESTED = 3
_SCHEDULED_SCENARIO_TRIGGER = 1
_RANDOM_STREAM_COUNT_V6 = 4
_MEMORY_INTEGER = 1
_MEMORY_BOOLEAN = 2
_MEMORY_UNIT = 3
_MEMORY_STRING = 4
_MEMORY_QUANTITY = 5
_MEMORY_OPTION_SOME = 6
_MEMORY_OPTION_NONE = 7
_MEMORY_LIST = 8
_MEMORY_RECORD = 9
_MEMORY_DURATION = 1
_MEMORY_DISTANCE = 2
_MEMORY_ANGLE = 3
_MEMORY_PROBABILITY = 4
_MAX_MEMORY_TEXT_BYTES = MAX_RUNTIME_STRING_BYTES
_MAX_MEMORY_INTEGER_BYTES = 512
_MAX_MEMORY_UNSIGNED_INTEGER = (1 << (_MAX_MEMORY_INTEGER_BYTES * 8)) - 1


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
    """Encode one validated mission state in canonical binary version 6 form."""
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
    _encode_map_geometry(writer, state.map_geometry)
    _encode_movement_actions(writer, state.movement_actions)
    _encode_policy_memory(writer, state.policy_memory)
    _encode_policy_versions(writer, state.policy_versions)
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
    if len(streams.states) != _RANDOM_STREAM_COUNT_V6:
        raise ValueError("state format version 6 requires exactly four random streams")
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
    map_geometry = _decode_map_geometry(reader)
    movement_actions = _decode_movement_actions(reader, map_geometry)
    policy_memory = _decode_policy_memory(reader)
    policy_versions = _decode_policy_versions(reader)
    id_allocator = IdAllocator(tuple(reader.u64() for _ in IdKind))
    scheduled_events = _decode_scheduled_events(reader)
    random_streams = _decode_random_streams(reader)
    return MissionState(
        tick=tick,
        phase=phase,
        entities=entities,
        map_geometry=map_geometry,
        movement_actions=movement_actions,
        id_allocator=id_allocator,
        policy_memory=policy_memory,
        policy_versions=policy_versions,
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


def _encode_map_geometry(writer: _Writer, geometry: MapGeometry | None) -> None:
    if geometry is None:
        writer.u8(0, "map geometry presence")
        return
    writer.u8(1, "map geometry presence")
    _encode_rectangle(writer, geometry.bounds, "map bounds")
    writer.items(len(geometry.obstacles), "map obstacle count")
    for obstacle in geometry.obstacles:
        writer.i64(obstacle.obstacle_id.value, "map obstacle ID")
        writer.u64(obstacle.elevation.value, "map obstacle elevation")
        _encode_rectangle(writer, obstacle.bounds, "map obstacle bounds")


def _decode_map_geometry(reader: _Reader) -> MapGeometry | None:
    presence_offset = reader.offset
    presence = reader.u8()
    if presence == 0:
        return None
    if presence != 1:
        raise _DecodeError(
            StateDecodeCode.INVALID_VALUE,
            presence_offset,
            f"invalid map geometry presence tag {presence}",
        )
    bounds = _decode_rectangle(reader)
    obstacles = tuple(
        MapObstacle(
            obstacle_id=ObstacleId(reader.i64()),
            elevation=ElevationLayer(reader.u64()),
            bounds=_decode_rectangle(reader),
        )
        for _ in range(reader.items("map obstacle count"))
    )
    return MapGeometry(bounds, obstacles)


def _encode_movement_actions(writer: _Writer, actions: tuple[MovementAction, ...]) -> None:
    writer.items(len(actions), "movement action count")
    for action in actions:
        writer.i64(action.entity_id.value, "movement action entity ID")
        writer.u32(action.next_waypoint_index, "movement action next waypoint index")
        writer.u64(action.segment_progress, "movement action segment progress")
        writer.u8(int(action.origin_event_id is not None), "movement action origin event presence")
        if action.origin_event_id is not None:
            writer.u64(action.origin_event_id.value, "movement action origin event ID")
        writer.items(len(action.path.waypoints), "movement action waypoint count")
        for waypoint in action.path.waypoints:
            writer.i64(waypoint.x.value, "movement action waypoint x")
            writer.i64(waypoint.y.value, "movement action waypoint y")
            writer.u64(waypoint.elevation.value, "movement action waypoint elevation")


def _decode_movement_actions(
    reader: _Reader, map_geometry: MapGeometry | None
) -> tuple[MovementAction, ...]:
    count = reader.items("movement action count")
    if count and map_geometry is None:
        raise _DecodeError(
            StateDecodeCode.INVALID_VALUE,
            reader.offset - 4,
            "movement actions require map geometry",
        )
    actions: list[MovementAction] = []
    for _ in range(count):
        entity_id = EntityId(reader.i64())
        next_waypoint_index = reader.u32()
        segment_progress = reader.u64()
        origin_presence_offset = reader.offset
        origin_presence = reader.u8()
        if origin_presence not in (0, 1):
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                origin_presence_offset,
                f"invalid movement action origin event presence tag {origin_presence}",
            )
        origin_event_id = EventId(reader.u64()) if origin_presence else None
        waypoint_count_offset = reader.offset
        waypoint_count = reader.items("movement action waypoint count")
        if waypoint_count < 2:
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                waypoint_count_offset,
                "movement action path requires at least two waypoints",
            )
        waypoints = tuple(
            WorldPosition(
                x=WorldSubunits(reader.i64()),
                y=WorldSubunits(reader.i64()),
                elevation=ElevationLayer(reader.u64()),
            )
            for _ in range(waypoint_count)
        )
        if map_geometry is None:
            raise AssertionError("movement action decoding requires map geometry")
        actions.append(
            MovementAction(
                entity_id,
                Path(PathQuery(map_geometry, waypoints[0], waypoints[-1]), waypoints),
                next_waypoint_index,
                segment_progress,
                origin_event_id,
            )
        )
    return tuple(actions)


def _encode_rectangle(writer: _Writer, rectangle: WorldRectangle, name: str) -> None:
    writer.i64(rectangle.minimum_x.value, f"{name} minimum x")
    writer.i64(rectangle.minimum_y.value, f"{name} minimum y")
    writer.i64(rectangle.maximum_x.value, f"{name} maximum x")
    writer.i64(rectangle.maximum_y.value, f"{name} maximum y")


def _decode_rectangle(reader: _Reader) -> WorldRectangle:
    return WorldRectangle(
        minimum_x=WorldSubunits(reader.i64()),
        minimum_y=WorldSubunits(reader.i64()),
        maximum_x=WorldSubunits(reader.i64()),
        maximum_y=WorldSubunits(reader.i64()),
    )


def _encode_policy_memory(writer: _Writer, store: PolicyMemoryStore) -> None:
    writer.items(len(store.entries), "policy memory entry count")
    for entry in store.entries:
        writer.i64(entry.entity_id.value, "policy memory entity ID")
        _encode_memory_value(writer, entry.value, 0)


def _decode_policy_memory(reader: _Reader) -> PolicyMemoryStore:
    count = reader.items("policy memory entry count")
    entries: list[EntityPolicyMemory] = []
    for _ in range(count):
        entity_id = EntityId(reader.i64())
        value = _decode_memory_value(reader, 0)
        if not isinstance(value, RecordValue):
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                reader.offset,
                "policy memory root value must be a record",
            )
        entries.append(EntityPolicyMemory(entity_id, value))
    return PolicyMemoryStore(tuple(entries))


def _encode_policy_versions(writer: _Writer, store: PolicyVersionStore) -> None:
    writer.items(len(store.entries), "policy version count")
    for entry in store.entries:
        writer.i64(entry.entity_id.value, "policy version entity ID")
        writer.write(entry.version.digest)


def _decode_policy_versions(reader: _Reader) -> PolicyVersionStore:
    entries: list[EntityPolicyVersion] = []
    for _ in range(reader.items("policy version count")):
        entity_id = EntityId(reader.i64())
        version = PolicyVersion(reader.read(POLICY_VERSION_DIGEST_BYTES))
        entries.append(EntityPolicyVersion(entity_id, version))
    return PolicyVersionStore(tuple(entries))


def _encode_memory_value(writer: _Writer, value: RuntimeValue, depth: int) -> None:
    if depth >= MAX_POLICY_MEMORY_DEPTH:
        raise ValueError("policy memory value exceeds the configured nesting limit")
    if not is_persistable_memory_value(value, depth):
        raise ValueError("policy memory value is not persistable")
    if isinstance(value, IntegerValue):
        writer.u8(_MEMORY_INTEGER, "policy memory value tag")
        writer.integer(value.value, "policy memory integer")
    elif isinstance(value, BooleanValue):
        writer.u8(_MEMORY_BOOLEAN, "policy memory value tag")
        writer.u8(int(value.value), "policy memory boolean")
    elif isinstance(value, UnitValue):
        writer.u8(_MEMORY_UNIT, "policy memory value tag")
    elif isinstance(value, StringValue):
        writer.u8(_MEMORY_STRING, "policy memory value tag")
        writer.text(value.value, "policy memory string")
    elif isinstance(value, QuantityValue):
        writer.u8(_MEMORY_QUANTITY, "policy memory value tag")
        _encode_memory_quantity(writer, value.value)
    elif isinstance(value, OptionSomeValue):
        writer.u8(_MEMORY_OPTION_SOME, "policy memory value tag")
        _encode_memory_value(writer, value.value, depth + 1)
    elif isinstance(value, OptionNoneValue):
        writer.u8(_MEMORY_OPTION_NONE, "policy memory value tag")
    elif isinstance(value, ListValue):
        writer.u8(_MEMORY_LIST, "policy memory value tag")
        writer.items(len(value.values), "policy memory list item count")
        for item in value.values:
            _encode_memory_value(writer, item, depth + 1)
    elif isinstance(value, RecordValue):
        writer.u8(_MEMORY_RECORD, "policy memory value tag")
        writer.text(value.type_name, "policy memory record type")
        writer.items(len(value.field_names), "policy memory record field count")
        for field_name, field_value in zip(value.field_names, value.values, strict=True):
            writer.text(field_name, "policy memory record field")
            _encode_memory_value(writer, field_value, depth + 1)
    else:
        raise ValueError("policy memory value is not persistable")


def _decode_memory_value(reader: _Reader, depth: int) -> RuntimeValue:
    if depth >= MAX_POLICY_MEMORY_DEPTH:
        raise _DecodeError(
            StateDecodeCode.INVALID_VALUE,
            reader.offset,
            "policy memory value exceeds the configured nesting limit",
        )
    tag_offset = reader.offset
    tag = reader.u8()
    if tag == _MEMORY_INTEGER:
        return IntegerValue(reader.integer("policy memory integer"))
    if tag == _MEMORY_BOOLEAN:
        value = reader.u8()
        if value not in (0, 1):
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                reader.offset - 1,
                "policy memory boolean must be zero or one",
            )
        return BooleanValue(bool(value))
    if tag == _MEMORY_UNIT:
        return UnitValue()
    if tag == _MEMORY_STRING:
        return StringValue(reader.text("policy memory string", _MAX_MEMORY_TEXT_BYTES))
    if tag == _MEMORY_QUANTITY:
        return QuantityValue(_decode_memory_quantity(reader))
    if tag == _MEMORY_OPTION_SOME:
        return OptionSomeValue(_decode_memory_value(reader, depth + 1))
    if tag == _MEMORY_OPTION_NONE:
        return OptionNoneValue()
    if tag == _MEMORY_LIST:
        return ListValue(
            tuple(
                _decode_memory_value(reader, depth + 1)
                for _ in range(reader.items("policy memory list item count"))
            )
        )
    if tag == _MEMORY_RECORD:
        type_name = reader.text("policy memory record type", _MAX_MEMORY_TEXT_BYTES)
        count = reader.items("policy memory record field count")
        field_names: list[str] = []
        values: list[RuntimeValue] = []
        for _ in range(count):
            field_names.append(reader.text("policy memory record field", _MAX_MEMORY_TEXT_BYTES))
            values.append(_decode_memory_value(reader, depth + 1))
        return RecordValue(type_name, tuple(field_names), tuple(values))
    raise _DecodeError(
        StateDecodeCode.INVALID_VALUE,
        tag_offset,
        f"invalid policy memory value tag {tag}",
    )


def _encode_memory_quantity(writer: _Writer, quantity: Quantity) -> None:
    tags = {
        QuantityDimension.DURATION: _MEMORY_DURATION,
        QuantityDimension.DISTANCE: _MEMORY_DISTANCE,
        QuantityDimension.ANGLE: _MEMORY_ANGLE,
        QuantityDimension.PROBABILITY: _MEMORY_PROBABILITY,
    }
    writer.u8(tags[quantity.dimension], "policy memory quantity dimension")
    writer.integer(quantity.value.numerator, "policy memory quantity numerator")
    writer.natural(quantity.value.denominator, "policy memory quantity denominator")


def _decode_memory_quantity(reader: _Reader) -> Quantity:
    offset = reader.offset
    dimensions = {
        _MEMORY_DURATION: QuantityDimension.DURATION,
        _MEMORY_DISTANCE: QuantityDimension.DISTANCE,
        _MEMORY_ANGLE: QuantityDimension.ANGLE,
        _MEMORY_PROBABILITY: QuantityDimension.PROBABILITY,
    }
    dimension = dimensions.get(reader.u8())
    if dimension is None:
        raise _DecodeError(
            StateDecodeCode.INVALID_VALUE,
            offset,
            "invalid policy memory quantity dimension",
        )
    numerator = reader.integer("policy memory quantity numerator")
    denominator = reader.natural("policy memory quantity denominator")
    rational = ExactRational(numerator, denominator)
    if rational.numerator != numerator or rational.denominator != denominator:
        raise _DecodeError(
            StateDecodeCode.INVALID_VALUE,
            offset,
            "policy memory quantity must use a reduced rational",
        )
    return Quantity(dimension, rational)


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
        RandomStreamState(reader.u64(), reader.u64()) for _ in range(_RANDOM_STREAM_COUNT_V6)
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

    def text(self, value: str, name: str) -> None:
        if not isinstance(value, str):
            raise TypeError(f"{name} must be text")
        encoded = value.encode("utf-8")
        if len(encoded) > _MAX_MEMORY_TEXT_BYTES:
            raise ValueError(f"{name} exceeds the configured byte limit")
        self.u32(len(encoded), f"{name} byte length")
        self.write(encoded)

    def integer(self, value: int, name: str) -> None:
        value = self._bounded(
            value,
            -_MAX_MEMORY_UNSIGNED_INTEGER,
            _MAX_MEMORY_UNSIGNED_INTEGER,
            name,
        )
        magnitude = abs(value)
        count = (magnitude.bit_length() + 7) // 8
        if count > _MAX_MEMORY_INTEGER_BYTES:
            raise ValueError(f"{name} exceeds the configured byte limit")
        self.u8(int(value < 0), f"{name} sign")
        self.u16(count, f"{name} byte length")
        if count:
            self.write(magnitude.to_bytes(count, "big"))

    def natural(self, value: int, name: str) -> None:
        value = self._bounded(value, 1, _MAX_MEMORY_UNSIGNED_INTEGER, name)
        count = (value.bit_length() + 7) // 8
        if count > _MAX_MEMORY_INTEGER_BYTES:
            raise ValueError(f"{name} exceeds the configured byte limit")
        self.u16(count, f"{name} byte length")
        self.write(value.to_bytes(count, "big"))

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

    def text(self, name: str, maximum_length: int) -> str:
        length_offset = self.offset
        length = self.u32()
        if length > maximum_length:
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                length_offset,
                f"{name} exceeds the configured byte limit",
            )
        text_offset = self.offset
        try:
            return self.read(length).decode("utf-8")
        except UnicodeDecodeError:
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                text_offset,
                f"{name} is not valid UTF-8",
            ) from None

    def integer(self, name: str) -> int:
        sign_offset = self.offset
        sign = self.u8()
        if sign not in (0, 1):
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                sign_offset,
                f"{name} sign must be zero or one",
            )
        length_offset = self.offset
        length = self.u16()
        if length > _MAX_MEMORY_INTEGER_BYTES:
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                length_offset,
                f"{name} exceeds the configured byte limit",
            )
        magnitude_offset = self.offset
        magnitude_bytes = self.read(length)
        if not magnitude_bytes:
            if sign:
                raise _DecodeError(
                    StateDecodeCode.INVALID_VALUE,
                    sign_offset,
                    f"{name} must not encode negative zero",
                )
            return 0
        if magnitude_bytes[0] == 0:
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                magnitude_offset,
                f"{name} has a noncanonical leading zero",
            )
        magnitude = int.from_bytes(magnitude_bytes, "big")
        return -magnitude if sign else magnitude

    def natural(self, name: str) -> int:
        length_offset = self.offset
        length = self.u16()
        if not 1 <= length <= _MAX_MEMORY_INTEGER_BYTES:
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                length_offset,
                f"{name} byte length is invalid",
            )
        magnitude_offset = self.offset
        magnitude_bytes = self.read(length)
        if magnitude_bytes[0] == 0:
            raise _DecodeError(
                StateDecodeCode.INVALID_VALUE,
                magnitude_offset,
                f"{name} has a noncanonical leading zero",
            )
        return int.from_bytes(magnitude_bytes, "big")

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
