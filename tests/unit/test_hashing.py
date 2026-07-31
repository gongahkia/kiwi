from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import IdAllocator
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
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.state import MissionPhase, MissionState, add_entity


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
    assert first.hex == "a3732d09003fa897c2eb33ba7b3431b2ab749b37fe6a84482a240a4819aef863"


@pytest.mark.parametrize(
    ("data", "code"),
    (
        (b"", StateDecodeCode.INVALID_MAGIC),
        (CANONICAL_STATE_MAGIC + b"\x00\x02", StateDecodeCode.UNSUPPORTED_VERSION),
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
