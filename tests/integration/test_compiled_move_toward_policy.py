from __future__ import annotations

from pathlib import Path

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import IdAllocator
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
from kiwi.sim.events import (
    IntentionEmitted,
    IntentionSelected,
    MovementArrived,
    MovementRouteRejected,
    MovementRouteStarted,
)
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.map_geometry import MapGeometry, MapObstacle
from kiwi.sim.pathing import PathQueryCode
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.runner import run_headless
from kiwi.sim.state import MissionState, add_entity

FIXTURE_PATH = (
    Path(__file__).resolve().parents[1] / "fixtures" / "policies" / "move_toward_policy.dtr"
)
MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_compiled_move_toward_policy_reaches_objective_around_an_obstacle() -> None:
    source = SourceFile(
        SourceFileId("tests/fixtures/policies/move_toward_policy.dtr"),
        FIXTURE_PATH.read_text(encoding="utf-8"),
    )
    artifact = _compile(source)
    state, bindings, objective = _mission_with_compiled_policy(artifact)
    clock = FixedTickClock(TickRate.HZ_30)
    start = StartMission(CommandHeader(0, 0, CommandSource.SCENARIO))

    first = run_headless(
        state, clock, 42, (start,), checkpoint_interval=1, policy_bindings=bindings
    )
    second = run_headless(
        state, clock, 42, (start,), checkpoint_interval=1, policy_bindings=bindings
    )

    emitted = tuple(event for event in first.events if isinstance(event, IntentionEmitted))
    selected = tuple(event for event in first.events if isinstance(event, IntentionSelected))
    routes = tuple(event for event in first.events if isinstance(event, MovementRouteStarted))
    arrivals = tuple(event for event in first.events if isinstance(event, MovementArrived))
    move_text = "MoveToward { target = Position { x = 2m, y = 0m } }"
    move_start = source.text.index(move_text)

    assert first.events == second.events
    assert first.checkpoints == second.checkpoints
    assert hash_canonical_state(first.state) == hash_canonical_state(second.state)
    assert first.state.entities[0].position == objective
    assert first.state.movement_actions == ()
    assert len(emitted) == len(selected) == 42
    assert len(routes) == len(arrivals) == 1
    assert not any(isinstance(event, MovementRouteRejected) for event in first.events)
    assert routes[0].path.waypoints == (
        WorldPosition(WorldSubunits(-2_000), WorldSubunits(0)),
        WorldPosition(WorldSubunits(-851), WorldSubunits(-851)),
        WorldPosition(WorldSubunits(851), WorldSubunits(-851)),
        objective,
    )
    assert emitted[0].candidate.origin.source_span == source.span(
        ByteOffset(move_start), ByteOffset(move_start + len(move_text))
    )
    assert routes[0].header.parent_event_ids == (selected[0].header.event_id,)
    assert arrivals[0].header.parent_event_ids == (routes[0].header.event_id,)


def test_compiled_move_toward_policy_emits_a_structured_route_failure_without_a_map() -> None:
    source = SourceFile(
        SourceFileId("tests/fixtures/policies/move_toward_policy.dtr"),
        FIXTURE_PATH.read_text(encoding="utf-8"),
    )
    artifact = _compile(source)
    state, entity = add_entity(
        MissionState(), WorldPosition(WorldSubunits(-2_000), WorldSubunits(0))
    )
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                artifact,
                FunctionId(0),
                MEMORY_SCHEMA,
                RecordValue("Memory", ("label",), (StringValue("ready"),)),
            ),
        )
    )

    result = run_headless(
        state,
        FixedTickClock(TickRate.HZ_30),
        1,
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
        policy_bindings=bindings,
    )

    selected = next(event for event in result.events if isinstance(event, IntentionSelected))
    rejected = next(event for event in result.events if isinstance(event, MovementRouteRejected))

    assert rejected.failure.code is PathQueryCode.MISSING_MAP
    assert rejected.header.parent_event_ids == (selected.header.event_id,)
    assert result.state.movement_actions == ()


def _mission_with_compiled_policy(
    artifact: CompiledArtifact,
) -> tuple[MissionState, PolicyBindings, WorldPosition]:
    obstacle_id, allocator = IdAllocator().allocate_obstacle()
    geometry = MapGeometry(
        WorldRectangle(
            WorldSubunits(-5_000),
            WorldSubunits(-5_000),
            WorldSubunits(5_000),
            WorldSubunits(5_000),
        ),
        (
            MapObstacle(
                obstacle_id,
                WorldRectangle(
                    WorldSubunits(-500),
                    WorldSubunits(-500),
                    WorldSubunits(500),
                    WorldSubunits(500),
                ),
            ),
        ),
    )
    state, entity = add_entity(
        MissionState(map_geometry=geometry, id_allocator=allocator),
        WorldPosition(WorldSubunits(-2_000), WorldSubunits(0)),
    )
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                artifact,
                FunctionId(0),
                MEMORY_SCHEMA,
                RecordValue("Memory", ("label",), (StringValue("ready"),)),
            ),
        )
    )
    return state, bindings, WorldPosition(WorldSubunits(2_000), WorldSubunits(0))


def _compile(source: SourceFile) -> CompiledArtifact:
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
