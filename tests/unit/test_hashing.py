from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import IdAllocator
from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.runtime_values import (
    BooleanValue,
    IntegerValue,
    ListValue,
    OptionSomeValue,
    QuantityValue,
    RecordValue,
    StringValue,
)
from kiwi.sim.hashing import (
    CANONICAL_STATE_MAGIC,
    CANONICAL_STATE_VERSION,
    StateDecodeCode,
    StateDecodeFailure,
    StateHash,
    decode_canonical_state,
    encode_canonical_state,
    hash_canonical_state,
)
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.memory import PolicyMemoryStore
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.policy_versions import PolicyVersion, PolicyVersionStore
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.state import MissionPhase, MissionState, MovementAction, add_entity


def _map_geometry() -> tuple[MapGeometry, IdAllocator]:
    obstacle_id, allocator = IdAllocator().allocate_obstacle()
    bounds = WorldRectangle(
        WorldSubunits(-1_000), WorldSubunits(-2_000), WorldSubunits(3_000), WorldSubunits(4_000)
    )
    obstacle = MapObstacle(
        obstacle_id,
        WorldRectangle(
            WorldSubunits(-500), WorldSubunits(-500), WorldSubunits(500), WorldSubunits(500)
        ),
        ElevationLayer(2),
    )
    return MapGeometry(bounds, (obstacle,)), allocator


def test_canonical_state_codec_round_trips_and_reencodes_identically() -> None:
    state = MissionState(
        tick=7,
        phase=MissionPhase.ACTIVE,
        random_streams=RandomStreams.from_seed(MissionSeed(9)),
    )
    state, _ = add_entity(state, WorldPosition(WorldSubunits(-2_000), WorldSubunits(5_000)))
    _, queue = state.scheduled_events.schedule(7, ScheduledEventKind.SCENARIO_TRIGGER)
    state = replace(state, scheduled_events=queue)

    encoded = encode_canonical_state(state)
    decoded = decode_canonical_state(encoded)

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert encode_canonical_state(decoded) == encoded
    assert encoded.startswith(CANONICAL_STATE_MAGIC + CANONICAL_STATE_VERSION.to_bytes(2, "big"))


def test_canonical_state_hash_is_stable_and_tracks_authoritative_changes() -> None:
    state = MissionState(random_streams=RandomStreams.from_seed(MissionSeed(12)))

    first = hash_canonical_state(state)
    repeated = hash_canonical_state(state)
    changed = hash_canonical_state(replace(state, phase=MissionPhase.ACTIVE))

    assert first == repeated
    assert first != changed
    assert first.hex == "0410e8888393371a0846f853d2bf96e5413341775296c25e6d58e1b9d4d54ca3"


def test_canonical_state_codec_round_trips_map_geometry_and_hashes_it() -> None:
    map_geometry, id_allocator = _map_geometry()
    state = MissionState(map_geometry=map_geometry, id_allocator=id_allocator)

    encoded = encode_canonical_state(state)
    decoded = decode_canonical_state(encoded)

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert hash_canonical_state(state) != hash_canonical_state(
        MissionState(id_allocator=id_allocator)
    )

    map_presence_offset = len(CANONICAL_STATE_MAGIC) + 2 + 8 + 1 + 4
    malformed = encoded[:map_presence_offset] + b"\x02" + encoded[map_presence_offset + 1 :]
    invalid = decode_canonical_state(malformed)
    assert isinstance(invalid, StateDecodeFailure)
    assert invalid.code is StateDecodeCode.INVALID_VALUE


def test_canonical_state_codec_round_trips_movement_actions() -> None:
    map_geometry, id_allocator = _map_geometry()
    start = WorldPosition(WorldSubunits(-600), WorldSubunits(-1_500))
    goal = WorldPosition(WorldSubunits(-600), WorldSubunits(-1_000))
    state, entity = add_entity(
        MissionState(map_geometry=map_geometry, id_allocator=id_allocator),
        start,
    )
    path = Path(PathQuery(map_geometry, start, goal), (start, goal))
    state = replace(state, movement_actions=(MovementAction(entity.entity_id, path),))

    decoded = decode_canonical_state(encode_canonical_state(state))

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert hash_canonical_state(decoded) == hash_canonical_state(state)


def test_canonical_state_codec_round_trips_persisted_policy_memory() -> None:
    state, entity = add_entity(
        MissionState(), WorldPosition(WorldSubunits(-2_000), WorldSubunits(5_000))
    )
    memory = RecordValue(
        "Memory",
        ("enabled", "history", "target"),
        (
            BooleanValue(True),
            ListValue(
                (
                    IntegerValue(-7),
                    QuantityValue(Quantity(QuantityDimension.DISTANCE, ExactRational(3, 2))),
                )
            ),
            OptionSomeValue(RecordValue("Target", ("label",), (StringValue("alpha"),))),
        ),
    )
    state = replace(
        state,
        policy_memory=PolicyMemoryStore().with_memory(entity.entity_id, memory),
    )

    encoded = encode_canonical_state(state)
    decoded = decode_canonical_state(encoded)

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert encode_canonical_state(decoded) == encoded
    assert hash_canonical_state(state) != hash_canonical_state(
        replace(state, policy_memory=PolicyMemoryStore())
    )

    noncanonical_quantity = encoded.replace(
        b"\x05\x02\x00\x00\x01\x03\x00\x01\x02",
        b"\x05\x02\x00\x00\x01\x02\x00\x01\x02",
        1,
    )
    assert noncanonical_quantity != encoded
    malformed = decode_canonical_state(noncanonical_quantity)
    assert isinstance(malformed, StateDecodeFailure)
    assert malformed.code is StateDecodeCode.INVALID_VALUE


def test_canonical_state_codec_round_trips_policy_versions_and_hashes_them() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(3), WorldSubunits(4)))
    version = PolicyVersion(bytes(range(32)))
    state = replace(
        state,
        policy_versions=PolicyVersionStore().with_version(entity.entity_id, version),
    )

    encoded = encode_canonical_state(state)
    decoded = decode_canonical_state(encoded)

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert decoded.policy_versions.version_for(entity.entity_id) == version
    assert hash_canonical_state(state) != hash_canonical_state(
        replace(state, policy_versions=PolicyVersionStore())
    )


@pytest.mark.parametrize(
    ("data", "code"),
    (
        (b"", StateDecodeCode.INVALID_MAGIC),
        (CANONICAL_STATE_MAGIC + b"\x00\x01", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x02", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x03", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x04", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC, StateDecodeCode.TRUNCATED),
        (encode_canonical_state(MissionState()) + b"x", StateDecodeCode.TRAILING_BYTES),
    ),
)
def test_canonical_state_decoder_returns_structured_failures(
    data: bytes, code: StateDecodeCode
) -> None:
    decoded = decode_canonical_state(data)

    assert isinstance(decoded, StateDecodeFailure)
    assert decoded.code is code


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: encode_canonical_state(object()), "mission state"),  # type: ignore[arg-type]
        (lambda: StateHash(b""), "32 bytes"),
        (lambda: decode_canonical_state(bytearray()), "must be bytes"),  # type: ignore[arg-type]
        (
            lambda: encode_canonical_state(MissionState(id_allocator=IdAllocator((1,) * 10))),
            "one counter",
        ),
    ),
)
def test_canonical_state_codec_rejects_invalid_inputs(factory: object, message: str) -> None:
    with pytest.raises((TypeError, ValueError), match=message):
        factory()  # type: ignore[operator]
