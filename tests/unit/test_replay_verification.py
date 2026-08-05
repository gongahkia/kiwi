from __future__ import annotations

from dataclasses import replace

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.replay.format import ReplayCheckpoint, ReplayPacket
from kiwi.replay.recording import record_headless_run
from kiwi.replay.verification import (
    ReplayVerificationFailure,
    ReplayVerificationFailureCode,
    ReplayVerificationSuccess,
    verify_replay,
)
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, RequestAbort, StartMission
from kiwi.sim.hashing import StateHash
from kiwi.sim.policy_versions import EntityPolicyVersion, PolicyVersion
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.snapshot import capture_authority_snapshot
from kiwi.sim.state import MissionState, add_entity


def test_replay_verification_reconstructs_recorded_checkpoint_states() -> None:
    start = StartMission(CommandHeader(0, 1, CommandSource.SCENARIO))
    abort = RequestAbort(CommandHeader(1, 2, CommandSource.PLAYER))
    recorded = record_headless_run(
        MissionState(random_streams=RandomStreams.from_seed(MissionSeed(7))),
        FixedTickClock(TickRate.HZ_30),
        2,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
        commands=(start, abort),
    )

    verified = verify_replay(recorded.replay)

    assert isinstance(verified, ReplayVerificationSuccess)
    assert verified.state == recorded.run.state


def test_replay_verification_rejects_policy_version_mismatch() -> None:
    state, entity = add_entity(
        MissionState(),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
    )
    initial = capture_authority_snapshot(state)
    replay = ReplayPacket(
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
        policy_versions=(EntityPolicyVersion(entity.entity_id, PolicyVersion(b"p" * 32)),),
        initial_snapshot=initial,
        seed=state.random_streams.seed,
        tick_rate=TickRate.HZ_30,
        commands=(),
        checkpoints=(ReplayCheckpoint(initial.tick, initial.state_hash),),
    )

    verified = verify_replay(replay)

    assert isinstance(verified, ReplayVerificationFailure)
    assert verified.code is ReplayVerificationFailureCode.POLICY_VERSIONS


def test_replay_verification_rejects_checkpoint_hash_mismatch() -> None:
    recorded = record_headless_run(
        MissionState(),
        FixedTickClock(TickRate.HZ_30),
        1,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
    )
    replay = replace(
        recorded.replay,
        checkpoints=(
            recorded.replay.checkpoints[0],
            ReplayCheckpoint(1, StateHash(b"x" * 32)),
        ),
    )

    verified = verify_replay(replay)

    assert isinstance(verified, ReplayVerificationFailure)
    assert verified.code is ReplayVerificationFailureCode.CHECKPOINT_HASH
    assert verified.divergence is not None
    assert verified.divergence.checkpoint_index == 1
    assert verified.divergence.tick == 1
    assert verified.divergence.expected_hash == StateHash(b"x" * 32)
    assert verified.divergence.actual_hash == recorded.replay.checkpoints[1].state_hash


def test_replay_verification_reports_the_first_divergent_checkpoint() -> None:
    recorded = record_headless_run(
        MissionState(),
        FixedTickClock(TickRate.HZ_30),
        3,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
    )
    replay = replace(
        recorded.replay,
        checkpoints=(
            recorded.replay.checkpoints[0],
            ReplayCheckpoint(1, StateHash(b"a" * 32)),
            ReplayCheckpoint(2, StateHash(b"b" * 32)),
            recorded.replay.checkpoints[3],
        ),
    )

    verified = verify_replay(replay)

    assert isinstance(verified, ReplayVerificationFailure)
    assert verified.divergence is not None
    assert verified.divergence.checkpoint_index == 1
    assert verified.divergence.tick == 1
    assert verified.divergence.expected_hash == StateHash(b"a" * 32)
    assert verified.divergence.actual_hash == recorded.replay.checkpoints[1].state_hash
