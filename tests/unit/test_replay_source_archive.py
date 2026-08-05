from __future__ import annotations

from dataclasses import replace

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
from kiwi.replay.recording import RecordedReplay, record_headless_run
from kiwi.replay.source_archive import (
    SOURCE_ARCHIVE_MAGIC,
    SOURCE_ARCHIVE_VERSION,
    HistoricalSourceFile,
    ReplaySourceArchive,
    SourceArchiveDecodeFailure,
    SourceArchiveDecodeFailureCode,
    build_source_archive,
    decode_source_archive,
    encode_source_archive,
    source_archive_matches_replay,
)
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.state import MissionState, add_entity

MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_source_archive_round_trips_exact_historical_source_and_source_map() -> None:
    initial, entity = add_entity(
        MissionState(random_streams=RandomStreams.from_seed(MissionSeed(7))),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
    )
    source, artifact = _policy_artifact()
    binding = PolicyBinding(
        entity.entity_id,
        artifact,
        FunctionId(0),
        MEMORY_SCHEMA,
        RecordValue("Memory", ("label",), (StringValue("initial"),)),
    )
    recorded = record_headless_run(
        initial,
        FixedTickClock(TickRate.HZ_30),
        1,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
        commands=(StartMission(CommandHeader(0, 1, CommandSource.SCENARIO)),),
        policy_bindings=PolicyBindings((binding,)),
    )
    archive = build_source_archive(
        recorded.replay,
        (HistoricalSourceFile(source, artifact.bytecode.header.source_language_version),),
        PolicyBindings((binding,)),
    )

    decoded = decode_source_archive(encode_source_archive(archive))

    assert decoded == archive
    assert source_archive_matches_replay(recorded.replay, archive)
    assert archive.sources[0].source == source
    assert archive.policies[0].bytecode.source_map == artifact.bytecode.source_map
    span = archive.policies[0].bytecode.source_map.entries[0].span
    assert archive.sources[0].source.positions_of(span)[0].line >= 1


def test_source_archive_rejects_wrong_replay_and_tampered_source_hash() -> None:
    recorded, archive = _recorded_archive()
    encoded = encode_source_archive(archive)
    hash_offset = len(SOURCE_ARCHIVE_MAGIC) + 2 + 32 + 4 + 4 + len("historical-policy.dtr") + 4
    tampered = bytearray(encoded)
    tampered[hash_offset] ^= 1

    decoded = decode_source_archive(bytes(tampered))

    assert not source_archive_matches_replay(
        replace(recorded.replay, application_build="other-build"), archive
    )
    assert isinstance(decoded, SourceArchiveDecodeFailure)
    assert decoded.code is SourceArchiveDecodeFailureCode.INVALID_STRUCTURE


def test_source_archive_rejects_non_v1_and_trailing_bytes() -> None:
    _, archive = _recorded_archive()
    encoded = encode_source_archive(archive)

    unsupported = decode_source_archive(
        SOURCE_ARCHIVE_MAGIC + (SOURCE_ARCHIVE_VERSION + 1).to_bytes(2, "big")
    )
    trailing = decode_source_archive(encoded + b"x")

    assert isinstance(unsupported, SourceArchiveDecodeFailure)
    assert unsupported.code is SourceArchiveDecodeFailureCode.UNSUPPORTED_VERSION
    assert isinstance(trailing, SourceArchiveDecodeFailure)
    assert trailing.code is SourceArchiveDecodeFailureCode.TRAILING_BYTES


def _recorded_archive() -> tuple[RecordedReplay, ReplaySourceArchive]:
    initial, entity = add_entity(
        MissionState(),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
    )
    source, artifact = _policy_artifact()
    binding = PolicyBinding(
        entity.entity_id,
        artifact,
        FunctionId(0),
        MEMORY_SCHEMA,
        RecordValue("Memory", ("label",), (StringValue("initial"),)),
    )
    recorded = record_headless_run(
        initial,
        FixedTickClock(TickRate.HZ_30),
        1,
        application_build="test-build",
        simulation_version="sim-v1",
        mission_hash=b"m" * 32,
        policy_bindings=PolicyBindings((binding,)),
    )
    return (
        recorded,
        build_source_archive(
            recorded.replay,
            (HistoricalSourceFile(source, artifact.bytecode.header.source_language_version),),
            PolicyBindings((binding,)),
        ),
    )


def _policy_artifact() -> tuple[SourceFile, CompiledArtifact]:
    source = SourceFile(
        SourceFileId("historical-policy.dtr"),
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
    return source, compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
