from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.replay.format import (
    REPLAY_MAGIC,
    REPLAY_VERSION,
    ReplayCheckpoint,
    ReplayDecodeFailure,
    ReplayDecodeFailureCode,
    ReplayPacket,
    decode_replay,
    encode_replay,
)
from kiwi.sim.clock import TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, IssueSignal, SignalName, StartMission
from kiwi.sim.policy_versions import PolicyVersion, PolicyVersionStore
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.snapshot import capture_authority_snapshot
from kiwi.sim.state import MissionState, add_entity


def test_replay_packet_round_trips_canonically() -> None:
    replay = _replay()

    encoded = encode_replay(replay)
    decoded = decode_replay(encoded)

    assert decoded == replay
    assert encode_replay(replay) == encoded


@pytest.mark.parametrize("version", (0, REPLAY_VERSION + 1))
def test_replay_packet_rejects_all_non_v1_and_noncanonical_bytes(version: int) -> None:
    encoded = encode_replay(_replay())

    unsupported = decode_replay(REPLAY_MAGIC + version.to_bytes(2, "big") + b"{}")
    noncanonical = decode_replay(encoded + b" ")

    assert isinstance(unsupported, ReplayDecodeFailure)
    assert unsupported.code is ReplayDecodeFailureCode.UNSUPPORTED_VERSION
    assert isinstance(noncanonical, ReplayDecodeFailure)
    assert noncanonical.code is ReplayDecodeFailureCode.NONCANONICAL


def test_replay_packet_requires_consistent_initial_inputs_and_ordering() -> None:
    replay = _replay()

    with pytest.raises(ValueError, match="seed must match"):
        replace(replay, seed=MissionSeed(8))
    with pytest.raises(ValueError, match="canonical command order"):
        replace(replay, commands=tuple(reversed(replay.commands)))
    with pytest.raises(ValueError, match="first checkpoint"):
        replace(replay, checkpoints=(ReplayCheckpoint(1, replay.initial_snapshot.state_hash),))


def test_replay_packet_rejects_corrupt_initial_snapshot() -> None:
    replay = _replay()
    corrupt = replace(replay.initial_snapshot, canonical_state=b"")

    with pytest.raises(ValueError, match="initial snapshot is invalid"):
        replace(
            replay,
            initial_snapshot=corrupt,
            checkpoints=(ReplayCheckpoint(corrupt.tick, corrupt.state_hash),),
        )


def _replay() -> ReplayPacket:
    seed = MissionSeed(7)
    state, entity = add_entity(
        MissionState(random_streams=RandomStreams.from_seed(seed)),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
    )
    state = replace(
        state,
        policy_versions=PolicyVersionStore().with_version(
            entity.entity_id,
            PolicyVersion(b"p" * 32),
        ),
    )
    initial = capture_authority_snapshot(state)
    start = StartMission(CommandHeader(0, 1, CommandSource.SCENARIO))
    signal = IssueSignal(
        CommandHeader(3, 2, CommandSource.PLAYER),
        SignalName("advance"),
        entity.entity_id,
    )
    return ReplayPacket(
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
        policy_versions=state.policy_versions.entries,
        initial_snapshot=initial,
        seed=seed,
        tick_rate=TickRate.HZ_30,
        commands=(start, signal),
        checkpoints=(ReplayCheckpoint(initial.tick, initial.state_hash),),
    )
