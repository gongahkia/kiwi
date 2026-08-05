from __future__ import annotations

from dataclasses import replace
from pathlib import Path

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EventId, IntentionId
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import BooleanValue, RecordValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.conditions import InjurySeverity, OperativeCondition, OperativeConditionStore
from kiwi.sim.events import (
    DamageApplied,
    EventKind,
    FireFired,
    InjuryChanged,
    IntentionSelected,
    ProjectileAdvanced,
    ProjectileImpacted,
    SuppressionChanged,
)
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.state import EntityState, MissionState, add_entity
from kiwi.sim.weapons import Ammunition, EquippedWeapon, WeaponStore
from kiwi.trace.capture import capture_run_trace
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    TraceConsequenceKind,
    TraceEdgeKind,
    TraceLevel,
    WorldEventTrace,
)
from kiwi.trace.retention import TraceRetentionPolicy

FIXTURE_PATH = (
    Path(__file__).resolve().parents[1] / "fixtures" / "policies" / "projectile_impact_policy.dtr"
)
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("fired", BuiltinType.BOOL),))


def test_projectile_impact_fixture_is_deterministic_and_retains_causal_consequences() -> None:
    first, shooter, target, source = _run_fixture()
    second, _, _, _ = _run_fixture()

    fired = _only_event(first, FireFired)
    advances = tuple(event for event in first.events if isinstance(event, ProjectileAdvanced))
    impact_event = _only_event(first, ProjectileImpacted)
    damage = _only_event(first, DamageApplied)
    injury = _only_event(first, InjuryChanged)
    suppression = tuple(event for event in first.events if isinstance(event, SuppressionChanged))
    state_hash = hash_canonical_state(first.state)
    trace = capture_run_trace(first, state_hash)
    summary_trace = capture_run_trace(
        first,
        state_hash,
        retention_policy=TraceRetentionPolicy(TraceLevel.SUMMARY),
    )
    fire_text = "Fire { target = Position { x = 10m, y = 0m }, weapon_id = 1 }"
    fire_start = source.text.index(fire_text)

    assert first == second
    assert hash_canonical_state(first.state) == hash_canonical_state(second.state)
    assert hash_canonical_state(first.state) == state_hash
    assert trace.run_state_hash == summary_trace.run_state_hash == state_hash.digest
    assert tuple(checkpoint.tick for checkpoint in first.checkpoints) == (0, 1, 2, 3)
    assert tuple(event.header.tick for event in advances) == (0, 1)
    assert impact_event.header.tick == damage.header.tick == injury.header.tick == 2
    assert impact_event.impact.collision.kind.value == "operative"
    assert impact_event.impact.collision.target_id == target.entity_id
    assert impact_event.impact.source_intention == fired.resolution.candidate.origin
    assert impact_event.impact.source_intention.source_span == source.span(
        ByteOffset(fire_start), ByteOffset(fire_start + len(fire_text))
    )
    assert damage.header.parent_event_ids == (impact_event.header.event_id,)
    assert injury.header.parent_event_ids == (damage.header.event_id,)
    assert injury.source_intention == fired.resolution.candidate.origin
    assert injury.resolution.injury_before is InjurySeverity.SEVERE
    assert injury.resolution.injury_after is InjurySeverity.INCAPACITATED
    assert tuple(event.resolution.suppression_after for event in suppression) == (
        1_500,
        2_500,
        4_500,
    )
    assert tuple(event.header.parent_event_ids for event in suppression) == (
        (advances[0].header.event_id,),
        (advances[1].header.event_id,),
        (impact_event.header.event_id,),
    )
    assert first.state.projectiles.entries == ()
    assert first.state.weapons.entries[0].ammunition == Ammunition(1, 0)
    assert first.state.conditions.condition_for(target.entity_id) == OperativeCondition(
        target.entity_id, health=0, protection=0
    )
    assert first.state.suppressions.suppression_for(target.entity_id) == 4_500
    assert first.state.policy_memory.memory_for(shooter.entity_id) == RecordValue(
        "Memory", ("fired",), (BooleanValue(True),)
    )
    assert tuple(
        record.event_id for record in trace.records if isinstance(record, WorldEventTrace)
    ) == tuple(event.header.event_id for event in first.events)
    assert trace.level is TraceLevel.DECISION
    assert summary_trace.level is TraceLevel.SUMMARY
    assert EventKind.PROJECTILE_ADVANCED not in tuple(
        record.event_kind for record in summary_trace.records if isinstance(record, WorldEventTrace)
    )
    assert EventKind.INJURY_CHANGED in tuple(
        record.event_kind for record in summary_trace.records if isinstance(record, WorldEventTrace)
    )
    consequences = tuple(record for record in trace.records if isinstance(record, ConsequenceTrace))
    assert tuple(
        (record.kind, record.subject_entity_ids, record.event_id, record.summary)
        for record in consequences
    ) == (
        (
            TraceConsequenceKind.INJURY,
            (target.entity_id,),
            injury.header.event_id,
            "injury changed from severe to incapacitated",
        ),
    )
    fired_intention_id = fired.resolution.candidate.origin.intention_id
    selected = next(
        event
        for event in first.events
        if isinstance(event, IntentionSelected)
        and event.resolution.candidate.origin.intention_id == fired_intention_id
    )
    edges = tuple(
        (edge.source_node_id.value, edge.target_node_id.value, edge.kind) for edge in trace.edges
    )
    fired_origin_node_id = _intention_trace_node_id(trace, fired_intention_id)
    fired_resolution_node_id = _resolution_trace_node_id(trace, fired_intention_id)
    selected_world_node_id = _world_trace_node_id(trace, selected.header.event_id)
    impact_world_node_id = _world_trace_node_id(trace, impact_event.header.event_id)
    damage_world_node_id = _world_trace_node_id(trace, damage.header.event_id)
    injury_world_node_id = _world_trace_node_id(trace, injury.header.event_id)
    consequence_node_id = consequences[0].node_id.value
    assert (fired_origin_node_id, fired_resolution_node_id, TraceEdgeKind.VALIDATED_BY) in edges
    assert (fired_resolution_node_id, selected_world_node_id, TraceEdgeKind.CAUSED_EVENT) in edges
    assert (fired_origin_node_id, impact_world_node_id, TraceEdgeKind.CAUSED_EVENT) in edges
    assert (impact_world_node_id, damage_world_node_id, TraceEdgeKind.CAUSED_EVENT) in edges
    assert (damage_world_node_id, injury_world_node_id, TraceEdgeKind.CAUSED_EVENT) in edges
    assert (injury_world_node_id, consequence_node_id, TraceEdgeKind.CONTRIBUTED_TO) in edges


def _run_fixture() -> tuple[HeadlessRun, EntityState, EntityState, SourceFile]:
    source = SourceFile(
        SourceFileId(FIXTURE_PATH.relative_to(REPOSITORY_ROOT).as_posix()),
        FIXTURE_PATH.read_text(encoding="utf-8"),
    )
    artifact = _compile(source)
    state, shooter = add_entity(MissionState(), _position(0, 0))
    state, target = add_entity(state, _position(2_500, 0))
    weapon_id, allocator = state.id_allocator.allocate_weapon()
    state = replace(
        state,
        id_allocator=allocator,
        weapons=WeaponStore((EquippedWeapon(weapon_id, shooter.entity_id, Ammunition(1, 1)),)),
        conditions=OperativeConditionStore((OperativeCondition(target.entity_id, 1, 0),)),
    )
    binding = PolicyBinding(
        shooter.entity_id,
        artifact,
        _entry_function_id(artifact),
        MEMORY_SCHEMA,
        RecordValue("Memory", ("fired",), (BooleanValue(False),)),
    )
    run = run_headless(
        state,
        FixedTickClock(TickRate.HZ_30),
        3,
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
        checkpoint_interval=1,
        policy_bindings=PolicyBindings((binding,)),
    )
    return run, shooter, target, source


def _entry_function_id(artifact: CompiledArtifact) -> FunctionId:
    assert len(artifact.capability_manifest.entries) == 1
    return artifact.capability_manifest.entries[0].function_id


def _only_event[Event](run: HeadlessRun, event_type: type[Event]) -> Event:
    events = tuple(event for event in run.events if isinstance(event, event_type))
    assert len(events) == 1
    return events[0]


def _intention_trace_node_id(trace: CausalTrace, intention_id: IntentionId) -> int:
    for record in trace.records:
        if isinstance(record, IntentionTrace) and record.origin.intention_id == intention_id:
            return record.node_id.value
    raise AssertionError("trace has no retained intention origin")


def _resolution_trace_node_id(trace: CausalTrace, intention_id: IntentionId) -> int:
    for record in trace.records:
        if isinstance(record, IntentionResolutionTrace) and record.intention_id == intention_id:
            return record.node_id.value
    raise AssertionError("trace has no retained intention resolution")


def _world_trace_node_id(trace: CausalTrace, event_id: EventId) -> int:
    for record in trace.records:
        if isinstance(record, WorldEventTrace) and record.event_id == event_id:
            return record.node_id.value
    raise AssertionError("trace has no retained world event")


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def _compile(source: SourceFile) -> CompiledArtifact:
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
