from __future__ import annotations

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import IdAllocator, IntentionId
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
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.cover_intentions import TakeCoverRejectionReason
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)
from kiwi.sim.events import CoverReservationGranted, CoverReservationRejected, IntentionSelected
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.runner import run_headless
from kiwi.sim.state import MissionState, add_entity

MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_compiled_take_cover_policy_reserves_cover_and_retains_contention_causality() -> None:
    source = SourceFile(
        SourceFileId("take-cover-policy.dtr"),
        "type SelfObservation = { entity_id: Int, position: Position }\n"
        "type Observation = { self: SelfObservation, tick: Int }\n"
        "type Memory = { label: String }\n"
        "type TakeCover = { cover_id: Int, side: String }\n"
        "type Decision = { intentions: List<TakeCover>, memory: Memory }\n"
        "policy reserve(observation: Observation, memory: Memory) -> Decision = "
        "Decision { "
        'intentions = [TakeCover { cover_id = 1, side = "left" }], '
        "memory = memory "
        "}\n",
    )
    artifact = _compile(source)
    state, bindings = _mission_with_compiled_policy(artifact)
    clock = FixedTickClock(TickRate.HZ_30)
    start = StartMission(CommandHeader(0, 0, CommandSource.SCENARIO))

    first = run_headless(state, clock, 1, (start,), checkpoint_interval=1, policy_bindings=bindings)
    second = run_headless(
        state, clock, 1, (start,), checkpoint_interval=1, policy_bindings=bindings
    )

    selected = tuple(event for event in first.events if isinstance(event, IntentionSelected))
    granted = tuple(event for event in first.events if isinstance(event, CoverReservationGranted))
    rejected = tuple(event for event in first.events if isinstance(event, CoverReservationRejected))
    take_cover_text = 'TakeCover { cover_id = 1, side = "left" }'
    take_cover_start = source.text.index(take_cover_text)

    assert first.events == second.events
    assert first.checkpoints == second.checkpoints
    assert hash_canonical_state(first.state) == hash_canonical_state(second.state)
    assert len(selected) == 2
    assert len(granted) == len(rejected) == 1
    assert first.state.cover_reservations.entries == (granted[0].reservation,)
    assert granted[0].resolution.candidate.origin.intention_id == IntentionId(1)
    assert granted[0].header.parent_event_ids == (selected[0].header.event_id,)
    assert rejected[0].resolution.reason is TakeCoverRejectionReason.SLOT_CONTESTED
    assert rejected[0].resolution.competing_intention_id == IntentionId(1)
    assert rejected[0].header.parent_event_ids == (selected[1].header.event_id,)
    assert granted[0].resolution.candidate.origin.source_span == source.span(
        ByteOffset(take_cover_start),
        ByteOffset(take_cover_start + len(take_cover_text)),
    )


def _mission_with_compiled_policy(
    artifact: CompiledArtifact,
) -> tuple[MissionState, PolicyBindings]:
    cover_id, allocator = IdAllocator().allocate_cover()
    cover = CoverSegment(
        cover_id,
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
        WorldPosition(WorldSubunits(1_000), WorldSubunits(0)),
        CoverHeight.HIGH,
        CoverIntegrity(10_000),
        (CoverSlot(0, WorldPosition(WorldSubunits(0), WorldSubunits(-350)), CoverSide.LEFT),),
    )
    state, first = add_entity(
        MissionState(covers=CoverStore((cover,)), id_allocator=allocator),
        WorldPosition(WorldSubunits(-1_000), WorldSubunits(0)),
    )
    state, second = add_entity(state, WorldPosition(WorldSubunits(-2_000), WorldSubunits(0)))
    initial_memory = RecordValue("Memory", ("label",), (StringValue("ready"),))
    bindings = PolicyBindings(
        (
            PolicyBinding(first.entity_id, artifact, FunctionId(0), MEMORY_SCHEMA, initial_memory),
            PolicyBinding(second.entity_id, artifact, FunctionId(0), MEMORY_SCHEMA, initial_memory),
        )
    )
    return state, bindings


def _compile(source: SourceFile) -> CompiledArtifact:
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
