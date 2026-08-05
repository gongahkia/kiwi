from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.replay.recording import record_headless_run
from kiwi.replay.seeking import (
    SEEK_MAGIC,
    SEEK_VERSION,
    ReplaySeekFailure,
    ReplaySeekFailureCode,
    ReplaySeekSuccess,
    SeekIndexDecodeFailure,
    SeekIndexDecodeFailureCode,
    build_seek_index,
    decode_seek_index,
    encode_seek_index,
    seek_replay,
)
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.runner import run_headless
from kiwi.sim.state import MissionState


def test_seek_index_round_trips_and_seeks_from_nearest_periodic_snapshot() -> None:
    initial = MissionState(random_streams=RandomStreams.from_seed(MissionSeed(7)))
    start = StartMission(CommandHeader(0, 1, CommandSource.SCENARIO))
    recorded = record_headless_run(
        initial,
        FixedTickClock(TickRate.HZ_30),
        5,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
        commands=(start,),
        checkpoint_interval=2,
    )
    index = build_seek_index(recorded.replay, recorded.run.checkpoints)

    decoded = decode_seek_index(encode_seek_index(index))
    sought = seek_replay(recorded.replay, index, 3)
    expected = run_headless(initial, FixedTickClock(TickRate.HZ_30), 3, (start,)).state

    assert decoded == index
    assert isinstance(sought, ReplaySeekSuccess)
    assert sought.snapshot_tick == 2
    assert sought.state == expected


def test_seek_index_rejects_non_v1_and_trailing_bytes() -> None:
    index = _index()
    encoded = encode_seek_index(index)

    unsupported = decode_seek_index(SEEK_MAGIC + (SEEK_VERSION + 1).to_bytes(2, "big"))
    trailing = decode_seek_index(encoded + b"x")

    assert isinstance(unsupported, SeekIndexDecodeFailure)
    assert unsupported.code is SeekIndexDecodeFailureCode.UNSUPPORTED_VERSION
    assert isinstance(trailing, SeekIndexDecodeFailure)
    assert trailing.code is SeekIndexDecodeFailureCode.TRAILING_BYTES


def test_seek_replay_rejects_a_sidecar_for_another_replay() -> None:
    index = _index()
    replay = _recorded().replay
    unrelated = replace(replay, application_build="other-build")

    sought = seek_replay(unrelated, index, 1)

    assert isinstance(sought, ReplaySeekFailure)
    assert sought.code is ReplaySeekFailureCode.REPLAY_HASH


def _index():
    recorded = _recorded()
    return build_seek_index(recorded.replay, recorded.run.checkpoints)


def _recorded():
    return record_headless_run(
        MissionState(),
        FixedTickClock(TickRate.HZ_30),
        2,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
        checkpoint_interval=1,
    )
