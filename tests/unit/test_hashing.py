from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import EventId, IdAllocator
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
from kiwi.sim.commands import CommandSource, SignalName
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactSighting,
    apply_contact_sightings,
)
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
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
from kiwi.sim.messages import MessageChannel, send_message
from kiwi.sim.pathing import Path, PathQuery
from kiwi.sim.policy_versions import PolicyVersion, PolicyVersionStore
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.signals import SignalObservation, SignalStore
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
    assert first.hex == "49bb78faaee4fab66ffc96e81ed4e47bdc96f7ecd922dcd88849ab9f09796f1a"


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


def test_canonical_state_codec_preserves_movement_action_causal_origin() -> None:
    map_geometry, id_allocator = _map_geometry()
    route_event_id, id_allocator = id_allocator.allocate_event()
    start = WorldPosition(WorldSubunits(-600), WorldSubunits(-1_500))
    goal = WorldPosition(WorldSubunits(-600), WorldSubunits(-1_000))
    state, entity = add_entity(
        MissionState(map_geometry=map_geometry, id_allocator=id_allocator),
        start,
    )
    path = Path(PathQuery(map_geometry, start, goal), (start, goal))
    state = replace(
        state,
        movement_actions=(MovementAction(entity.entity_id, path, origin_event_id=route_event_id),),
    )

    decoded = decode_canonical_state(encode_canonical_state(state))

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert decoded.movement_actions[0].origin_event_id == route_event_id
    assert hash_canonical_state(state) != hash_canonical_state(
        replace(state, movement_actions=(MovementAction(entity.entity_id, path),))
    )


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


def test_canonical_state_codec_round_trips_cover_segments_and_hashes_them() -> None:
    cover_id, allocator = IdAllocator().allocate_cover()
    cover = CoverSegment(
        cover_id,
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
        WorldPosition(WorldSubunits(1_000), WorldSubunits(0)),
        CoverHeight.HIGH,
        CoverIntegrity(8_500),
        (
            CoverSlot(0, WorldPosition(WorldSubunits(0), WorldSubunits(-350)), CoverSide.LEFT),
            CoverSlot(1, WorldPosition(WorldSubunits(1_000), WorldSubunits(350)), CoverSide.RIGHT),
        ),
    )
    state = MissionState(covers=CoverStore((cover,)), id_allocator=allocator)

    decoded = decode_canonical_state(encode_canonical_state(state))

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert decoded.covers.segment_for(cover_id) == cover
    assert hash_canonical_state(state) != hash_canonical_state(replace(state, covers=CoverStore()))


def test_canonical_state_codec_round_trips_contacts_and_hashes_them() -> None:
    state, owner = add_entity(MissionState(), WorldPosition(WorldSubunits(3), WorldSubunits(4)))
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    contacts, allocator = apply_contact_sightings(
        state.contacts,
        allocator,
        state.tick,
        (
            ContactSighting(
                owner.entity_id,
                WorldPosition(WorldSubunits(300), WorldSubunits(400), ElevationLayer(1)),
                WorldSubunits(200),
                ContactConfidence(8_000),
                _contact_provenance(evidence_event_id),
            ),
        ),
    )
    state = replace(state, contacts=contacts, id_allocator=allocator)

    decoded = decode_canonical_state(encode_canonical_state(state))

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert (
        decoded.contacts.estimate_for(owner.entity_id, contacts.estimates[0].contact_id)
        == contacts.estimates[0]
    )
    assert hash_canonical_state(state) != hash_canonical_state(
        replace(state, contacts=type(contacts)())
    )


def test_canonical_state_codec_round_trips_live_messages_and_hashes_them() -> None:
    initial, sender = add_entity(
        MissionState(tick=4), WorldPosition(WorldSubunits(3), WorldSubunits(4))
    )
    state, recipient = add_entity(initial, WorldPosition(WorldSubunits(5), WorldSubunits(6)))
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    sent = send_message(
        state.messages,
        allocator,
        sender.entity_id,
        recipient.entity_id,
        MessageChannel.RADIO,
        RecordValue("Status", ("label",), (StringValue("ready"),)),
        3,
        5,
        (evidence_event_id,),
    )
    state = replace(state, messages=sent.ledger, id_allocator=sent.id_allocator)

    decoded = decode_canonical_state(encode_canonical_state(state))

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert decoded.messages.messages == (sent.message,)
    assert hash_canonical_state(state) != hash_canonical_state(
        replace(state, messages=type(sent.ledger)())
    )


def test_canonical_state_codec_round_trips_current_signals_and_hashes_them() -> None:
    initial, first = add_entity(
        MissionState(tick=4), WorldPosition(WorldSubunits(3), WorldSubunits(4))
    )
    state, second = add_entity(initial, WorldPosition(WorldSubunits(5), WorldSubunits(6)))
    event_id, allocator = state.id_allocator.allocate_event()
    signals = SignalStore(
        (
            SignalObservation(
                SignalName("hold"),
                4,
                0,
                CommandSource.PLAYER,
                second.entity_id,
                event_id,
            ),
        )
    )
    state = replace(state, signals=signals, id_allocator=allocator)

    decoded = decode_canonical_state(encode_canonical_state(state))

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert decoded.signals.signals == signals.signals
    assert hash_canonical_state(state) != hash_canonical_state(
        replace(state, signals=SignalStore())
    )


def _contact_provenance(event_id: EventId) -> ContactProvenance:
    return ContactProvenance(
        tuple(ContactFieldProvenance(field, (event_id,)) for field in ContactField)
    )


@pytest.mark.parametrize(
    ("data", "code"),
    (
        (b"", StateDecodeCode.INVALID_MAGIC),
        (CANONICAL_STATE_MAGIC + b"\x00\x01", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x02", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x03", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x04", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x05", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x06", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x07", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x08", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x09", StateDecodeCode.UNSUPPORTED_VERSION),
        (CANONICAL_STATE_MAGIC + b"\x00\x0a", StateDecodeCode.UNSUPPORTED_VERSION),
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
