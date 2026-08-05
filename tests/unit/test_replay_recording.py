from __future__ import annotations

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import RecordValue, StringValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.replay.format import ReplayCheckpoint, decode_replay, encode_replay
from kiwi.replay.recording import record_headless_run
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, RequestAbort, StartMission
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.policy_versions import EntityPolicyVersion
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.snapshot import capture_authority_snapshot
from kiwi.sim.state import EntityState, MissionState, add_entity

MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_record_headless_run_retains_canonical_inputs_and_checkpoints() -> None:
    initial, entity, bindings = _initial_inputs()
    start = StartMission(CommandHeader(0, 2, CommandSource.SCENARIO))
    abort = RequestAbort(CommandHeader(1, 3, CommandSource.PLAYER))

    recorded = record_headless_run(
        initial,
        FixedTickClock(TickRate.HZ_30),
        2,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
        commands=(abort, start),
        checkpoint_interval=1,
        policy_bindings=bindings,
    )

    replay = recorded.replay
    assert replay.initial_snapshot == capture_authority_snapshot(initial)
    assert replay.seed == MissionSeed(7)
    assert replay.tick_rate is TickRate.HZ_30
    assert replay.mission_hash == b"m" * 32
    assert replay.policy_versions == (
        EntityPolicyVersion(entity.entity_id, bindings.entries[0].policy_version),
    )
    assert recorded.run.state.policy_versions.entries == replay.policy_versions
    assert replay.commands == (start, abort)
    assert replay.checkpoints == tuple(
        ReplayCheckpoint(checkpoint.tick, checkpoint.state_hash)
        for checkpoint in recorded.run.checkpoints
    )
    assert tuple(checkpoint.tick for checkpoint in replay.checkpoints) == (0, 1, 2)
    assert initial.policy_versions.entries == ()
    assert decode_replay(encode_replay(replay)) == replay


def test_replay_recording_rejects_policy_binding_without_initial_entity() -> None:
    _, _, bindings = _initial_inputs()

    with pytest.raises(ValueError, match="belong to initial mission entities"):
        record_headless_run(
            MissionState(),
            FixedTickClock(TickRate.HZ_30),
            0,
            application_build="test-build",
            simulation_version="sim-v1",
            mission_hash=b"m" * 32,
            policy_bindings=bindings,
        )


def _initial_inputs() -> tuple[MissionState, EntityState, PolicyBindings]:
    state, entity = add_entity(
        MissionState(random_streams=RandomStreams.from_seed(MissionSeed(7))),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
    )
    binding = PolicyBinding(
        entity.entity_id,
        _policy_artifact(),
        FunctionId(0),
        MEMORY_SCHEMA,
        RecordValue("Memory", ("label",), (StringValue("ready"),)),
    )
    return state, entity, PolicyBindings((binding,))


def _policy_artifact() -> CompiledArtifact:
    source = SourceFile(
        SourceFileId("replay-policy.dtr"),
        "type SelfObservation = { entity_id: Int, position: Position }\n"
        "type Observation = { self: SelfObservation, tick: Int }\n"
        "type Memory = { label: String }\n"
        "type Wait = { duration: Duration }\n"
        "type Decision = { intentions: List<Wait>, memory: Memory }\n"
        "policy decide(observation: Observation, memory: Memory) -> Decision = "
        "Decision { intentions = [Wait { duration = 1s }], memory = memory }\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
