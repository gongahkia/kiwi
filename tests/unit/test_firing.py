from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import ExpressionId, FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import RecordValue, StringValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.sim.arbitration import (
    ArbitrationStatus,
    IntentionArbitration,
    IntentionCandidate,
    PolicyArbitrationPhase,
)
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.events import FireFired, FireRejected, IntentionSelected, ProjectileAdvanced
from kiwi.sim.firing import (
    PROJECTILE_LIFETIME_TICKS,
    PROJECTILE_SPEED_MM_PER_TICK,
    FireRejectionReason,
    FireResolutionStatus,
    resolve_selected_fire,
)
from kiwi.sim.intentions import FireIntention, IntentionKind, IntentionOrigin
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.projectile_sweeps import sweep_projectiles
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.state import EntityState, MissionState, add_entity
from kiwi.sim.weapons import AimState, AimStore, Ammunition, EquippedWeapon, WeaponStore

MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_selected_fire_consumes_ammunition_resets_aim_and_spawns_a_generic_projectile() -> None:
    state, arbitration, shooter, weapon = _selected_fire_state(position(2_000, 0))

    phase = resolve_selected_fire(state, arbitration)

    resolution = phase.resolutions[0]
    assert resolution.status is FireResolutionStatus.FIRED
    assert resolution.projectile is not None
    assert resolution.projectile.position == shooter.position
    assert resolution.projectile.velocity.dx.value == PROJECTILE_SPEED_MM_PER_TICK
    assert resolution.projectile.velocity.dy.value == 0
    assert resolution.projectile.remaining_ticks == PROJECTILE_LIFETIME_TICKS
    assert phase.state.weapons.weapon_for(weapon.weapon_id) == EquippedWeapon(
        weapon.weapon_id,
        shooter.entity_id,
        Ammunition(3, 1),
    )
    assert phase.state.aim_states.quality_for(shooter.entity_id) == 0
    assert phase.state.projectiles.entries == (resolution.projectile,)
    assert sweep_projectiles(phase.state)[0].collision is None


@pytest.mark.parametrize(
    ("target", "loaded_rounds", "weapon_owner", "expected_reason"),
    (
        (
            WorldPosition(WorldSubunits(0), WorldSubunits(0)),
            1,
            "shooter",
            FireRejectionReason.TARGET_COINCIDENT,
        ),
        (
            WorldPosition(WorldSubunits(2_000), WorldSubunits(0)),
            0,
            "shooter",
            FireRejectionReason.AMMUNITION_EMPTY,
        ),
        (
            WorldPosition(WorldSubunits(2_000), WorldSubunits(0)),
            1,
            "other",
            FireRejectionReason.WEAPON_NOT_OWNED,
        ),
    ),
)
def test_selected_fire_rejects_invalid_authoritative_preconditions(
    target: WorldPosition,
    loaded_rounds: int,
    weapon_owner: str,
    expected_reason: FireRejectionReason,
) -> None:
    state, arbitration, _, _ = _selected_fire_state(target, loaded_rounds, weapon_owner)

    phase = resolve_selected_fire(state, arbitration)

    assert phase.state == state
    assert phase.resolutions[0].status is FireResolutionStatus.REJECTED
    assert phase.resolutions[0].reason is expected_reason


def test_selected_fire_rejects_an_unknown_weapon() -> None:
    state, arbitration, _, _ = _selected_fire_state(position(2_000, 0), include_weapon=False)

    phase = resolve_selected_fire(state, arbitration)

    assert phase.state == state
    assert phase.resolutions[0].reason is FireRejectionReason.WEAPON_NOT_FOUND


def test_compiled_fire_policy_spawns_and_advances_a_projectile() -> None:
    state, shooter = add_entity(MissionState(), position(0, 0))
    weapon_id, allocator = state.id_allocator.allocate_weapon()
    state = replace(
        state,
        id_allocator=allocator,
        weapons=WeaponStore((EquippedWeapon(weapon_id, shooter.entity_id, Ammunition(3, 2)),)),
        aim_states=AimStore((AimState(shooter.entity_id, 5_000),)),
    )
    binding = PolicyBinding(
        shooter.entity_id,
        _fire_policy_artifact(),
        FunctionId(0),
        MEMORY_SCHEMA,
        RecordValue("Memory", ("label",), (StringValue("ready"),)),
    )

    result = reduce_one_tick(
        state,
        FixedTickClock(TickRate.HZ_30),
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
        PolicyBindings((binding,)),
    )

    projectile = result.state.projectiles.entries[0]
    assert result.state.tick == 1
    assert projectile.position == position(1_000, 0)
    assert projectile.remaining_ticks == PROJECTILE_LIFETIME_TICKS - 1
    assert result.state.weapons.weapon_for(weapon_id) == EquippedWeapon(
        weapon_id, shooter.entity_id, Ammunition(3, 1)
    )
    assert result.state.aim_states.quality_for(shooter.entity_id) == 0
    selected = next(event for event in result.events if isinstance(event, IntentionSelected))
    fired = next(event for event in result.events if isinstance(event, FireFired))
    advanced = next(event for event in result.events if isinstance(event, ProjectileAdvanced))
    assert fired.header.parent_event_ids == (selected.header.event_id,)
    assert advanced.resolution.projectile == fired.resolution.projectile


def test_compiled_fire_policy_emits_a_selected_request_rejection() -> None:
    state, shooter = add_entity(MissionState(), position(0, 0))
    binding = PolicyBinding(
        shooter.entity_id,
        _fire_policy_artifact(),
        FunctionId(0),
        MEMORY_SCHEMA,
        RecordValue("Memory", ("label",), (StringValue("ready"),)),
    )

    result = reduce_one_tick(
        state,
        FixedTickClock(TickRate.HZ_30),
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
        PolicyBindings((binding,)),
    )

    selected = next(event for event in result.events if isinstance(event, IntentionSelected))
    rejected = next(event for event in result.events if isinstance(event, FireRejected))
    assert rejected.resolution.reason is FireRejectionReason.WEAPON_NOT_FOUND
    assert rejected.header.parent_event_ids == (selected.header.event_id,)


def test_compiled_aim_policy_preserves_automatic_aim_progression() -> None:
    state, shooter = add_entity(MissionState(), position(0, 0))
    binding = PolicyBinding(
        shooter.entity_id,
        _aim_policy_artifact(),
        FunctionId(0),
        MEMORY_SCHEMA,
        RecordValue("Memory", ("label",), (StringValue("ready"),)),
    )

    result = reduce_one_tick(
        state,
        FixedTickClock(TickRate.HZ_30),
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
        PolicyBindings((binding,)),
    )

    selected = tuple(event for event in result.events if isinstance(event, IntentionSelected))
    assert len(selected) == 1
    assert result.state.aim_states.quality_for(shooter.entity_id) == 333
    assert result.state.projectiles.entries == ()


def _selected_fire_state(
    target: WorldPosition,
    loaded_rounds: int = 2,
    weapon_owner: str = "shooter",
    include_weapon: bool = True,
) -> tuple[MissionState, PolicyArbitrationPhase, EntityState, EquippedWeapon]:
    state, shooter = add_entity(MissionState(), position(0, 0))
    state, other = add_entity(state, position(-1_000, 0))
    weapon_id, allocator = state.id_allocator.allocate_weapon()
    intention_id, allocator = allocator.allocate_intention()
    invocation_id, allocator = allocator.allocate_policy_invocation()
    owner = shooter if weapon_owner == "shooter" else other
    weapon = EquippedWeapon(weapon_id, owner.entity_id, Ammunition(3, loaded_rounds))
    state = replace(
        state,
        id_allocator=allocator,
        weapons=WeaponStore((weapon,)) if include_weapon else WeaponStore(),
        aim_states=AimStore((AimState(shooter.entity_id, 5_000),)),
    )
    source = SourceFile(SourceFileId("fire.dtr"), "Fire")
    candidate = IntentionCandidate(
        IntentionOrigin(
            intention_id,
            shooter.entity_id,
            invocation_id,
            ExpressionId(1),
            source.span(ByteOffset(0), ByteOffset(4)),
            0,
            state.tick,
            IntentionKind.FIRE,
        ),
        FireIntention(weapon_id, target),
    )
    arbitration = PolicyArbitrationPhase(
        state,
        (IntentionArbitration(candidate, ArbitrationStatus.SELECTED),),
    )
    return state, arbitration, shooter, weapon


def position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def _fire_policy_artifact() -> CompiledArtifact:
    source = SourceFile(
        SourceFileId("fire-policy.dtr"),
        "type Observation = { tick: Int }\n"
        "type Memory = { label: String }\n"
        "type Fire = { target: Position, weapon_id: Int }\n"
        "type Decision = { intentions: List<Fire>, memory: Memory }\n"
        "policy decide(observation: Observation, memory: Memory) -> Decision = "
        "Decision { "
        "intentions = [Fire { target = Position { x = 10m, y = 0m }, weapon_id = 1 }], "
        "memory = memory "
        "}\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))


def _aim_policy_artifact() -> CompiledArtifact:
    source = SourceFile(
        SourceFileId("aim-policy.dtr"),
        "type Observation = { tick: Int }\n"
        "type Memory = { label: String }\n"
        "type Aim = {}\n"
        "type Decision = { intentions: List<Aim>, memory: Memory }\n"
        "policy decide(observation: Observation, memory: Memory) -> Decision = "
        "Decision { intentions = [Aim {}], memory = memory }\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
