from __future__ import annotations

from dataclasses import replace
from pathlib import Path

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
from kiwi.dsl.runtime_values import BooleanValue, RecordValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.conditions import InjurySeverity, OperativeCondition, OperativeConditionStore
from kiwi.sim.events import (
    DamageApplied,
    FireFired,
    InjuryChanged,
    ProjectileAdvanced,
    ProjectileImpacted,
    SuppressionChanged,
)
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.state import EntityState, MissionState, add_entity
from kiwi.sim.weapons import Ammunition, EquippedWeapon, WeaponStore

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
    fire_text = "Fire { target = Position { x = 10m, y = 0m }, weapon_id = 1 }"
    fire_start = source.text.index(fire_text)

    assert first == second
    assert hash_canonical_state(first.state) == hash_canonical_state(second.state)
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


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def _compile(source: SourceFile) -> CompiledArtifact:
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
