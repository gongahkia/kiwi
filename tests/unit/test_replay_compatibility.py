from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EntityId
from kiwi.replay.compatibility import (
    PolicyVersionDifferenceKind,
    RunCompatibilityFailureCode,
    check_run_compatibility,
)
from kiwi.replay.format import ReplayCheckpoint, ReplayPacket
from kiwi.replay.recording import record_headless_run
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.policy_versions import EntityPolicyVersion, PolicyVersion
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.snapshot import capture_authority_snapshot
from kiwi.sim.state import MissionPhase, MissionState, add_entity


def test_run_compatibility_allows_and_reports_policy_version_changes() -> None:
    replay, entity_id = _replay()
    first = replace(
        replay,
        policy_versions=(EntityPolicyVersion(entity_id, PolicyVersion(b"a" * 32)),),
    )
    second = replace(
        replay,
        policy_versions=(EntityPolicyVersion(entity_id, PolicyVersion(b"b" * 32)),),
    )

    added = check_run_compatibility(replay, first)
    changed = check_run_compatibility(first, second)
    removed = check_run_compatibility(first, replay)

    assert added.is_compatible
    assert added.policy_differences[0].kind is PolicyVersionDifferenceKind.ADDED
    assert changed.is_compatible
    assert changed.policy_differences[0].kind is PolicyVersionDifferenceKind.CHANGED
    assert removed.is_compatible
    assert removed.policy_differences[0].kind is PolicyVersionDifferenceKind.REMOVED


def test_run_compatibility_reports_every_non_policy_baseline_mismatch_in_order() -> None:
    replay, _ = _replay()
    alternate_state = MissionState(
        phase=MissionPhase.ACTIVE,
        random_streams=RandomStreams.from_seed(replay.seed),
    )
    alternate_snapshot = capture_authority_snapshot(alternate_state)
    actual = replace(
        replay,
        application_build="other-build",
        simulation_version="sim-v2",
        mission_hash=b"x" * 32,
        initial_snapshot=alternate_snapshot,
        tick_rate=TickRate.HZ_20,
        commands=(StartMission(CommandHeader(0, 1, CommandSource.SCENARIO)),),
        checkpoints=(
            ReplayCheckpoint(alternate_snapshot.tick, alternate_snapshot.state_hash),
            replay.checkpoints[-1],
        ),
    )

    compatibility = check_run_compatibility(replay, actual)

    assert not compatibility.is_compatible
    assert tuple(failure.code for failure in compatibility.failures) == (
        RunCompatibilityFailureCode.APPLICATION_BUILD,
        RunCompatibilityFailureCode.SIMULATION_VERSION,
        RunCompatibilityFailureCode.MISSION,
        RunCompatibilityFailureCode.INITIAL_SNAPSHOT,
        RunCompatibilityFailureCode.TICK_RATE,
        RunCompatibilityFailureCode.COMMAND_LOG,
    )


def test_run_compatibility_reports_seed_mismatch_with_its_initial_snapshot() -> None:
    replay, _ = _replay()
    alternate_state = MissionState(random_streams=RandomStreams.from_seed(MissionSeed(9)))
    alternate_snapshot = capture_authority_snapshot(alternate_state)
    actual = replace(
        replay,
        initial_snapshot=alternate_snapshot,
        seed=MissionSeed(9),
        checkpoints=(
            ReplayCheckpoint(alternate_snapshot.tick, alternate_snapshot.state_hash),
            replay.checkpoints[-1],
        ),
    )

    compatibility = check_run_compatibility(replay, actual)

    assert tuple(failure.code for failure in compatibility.failures) == (
        RunCompatibilityFailureCode.INITIAL_SNAPSHOT,
        RunCompatibilityFailureCode.SEED,
    )


def test_run_compatibility_rejects_non_replay_inputs() -> None:
    replay, _ = _replay()

    with pytest.raises(TypeError, match="ReplayPacket"):
        check_run_compatibility(replay, object())  # type: ignore[arg-type]


def _replay() -> tuple[ReplayPacket, EntityId]:
    state, entity = add_entity(
        MissionState(random_streams=RandomStreams.from_seed(MissionSeed(7))),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
    )
    recorded = record_headless_run(
        state,
        FixedTickClock(TickRate.HZ_30),
        1,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
    )
    return recorded.replay, entity.entity_id
