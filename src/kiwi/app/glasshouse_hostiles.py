"""Headless Glasshouse hostile-roster construction through the same DSL boundary."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.app.glasshouse_players import (
    PLAYER_MEMORY_SCHEMA,
    GlasshousePlayerSetup,
    GlasshousePolicyFailure,
)
from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.capabilities import (
    AIM_CAPABILITY,
    MOVE_TOWARD_CAPABILITY,
    WAIT_CAPABILITY,
    CapabilityId,
)
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import RecordValue, StringValue
from kiwi.dsl.source import SourceFile
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.state import MissionState, add_entity
from kiwi.sim.weapons import Ammunition, EquippedWeapon, WeaponStore


class GlasshouseHostileRole(StrEnum):
    """The three initial project-authored hostile tactical roles."""

    PATROL = "patrol"
    SENTRY = "sentry"
    WARDEN = "warden"


@dataclass(frozen=True, slots=True)
class GlasshouseHostileLoadout:
    """One fixed hostile deployment, magazine, and closed-DSL policy contract."""

    role: GlasshouseHostileRole
    policy_file_id: str
    position_x: int
    position_y: int
    magazine_capacity: int
    capabilities: tuple[CapabilityId, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.role, GlasshouseHostileRole):
            raise ValueError("Glasshouse hostile loadout requires a role")
        if not isinstance(self.policy_file_id, str) or not self.policy_file_id:
            raise ValueError("Glasshouse hostile policy file ID must be text")
        if any(
            not isinstance(value, int) or isinstance(value, bool)
            for value in (self.position_x, self.position_y, self.magazine_capacity)
        ):
            raise ValueError(
                "Glasshouse hostile coordinates and magazine capacity must be integers"
            )
        if self.magazine_capacity <= 0:
            raise ValueError("Glasshouse hostile magazine capacity must be positive")
        names = tuple(capability.value for capability in self.capabilities)
        if names != tuple(sorted(names)) or len(set(names)) != len(names):
            raise ValueError("Glasshouse hostile capabilities must be lexically ordered and unique")


@dataclass(frozen=True, slots=True)
class GlasshouseHostileSetup:
    """One combined player/hostile authority state and compatible policy bindings."""

    state: MissionState
    policy_bindings: PolicyBindings

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("Glasshouse hostile setup requires mission state")
        if not isinstance(self.policy_bindings, PolicyBindings):
            raise ValueError("Glasshouse hostile setup requires policy bindings")
        if len(self.state.entities) != 7 or len(self.state.weapons.entries) != 7:
            raise ValueError("Glasshouse hostile setup requires four players and three hostiles")
        if tuple(binding.entity_id for binding in self.policy_bindings.entries) != tuple(
            entity.entity_id for entity in self.state.entities
        ):
            raise ValueError("Glasshouse hostile setup bindings must match every deployed entity")


def _capabilities(*capabilities: CapabilityId) -> tuple[CapabilityId, ...]:
    return tuple(sorted(capabilities, key=lambda capability: capability.value))


GLASSHOUSE_HOSTILE_LOADOUTS = (
    GlasshouseHostileLoadout(
        GlasshouseHostileRole.PATROL,
        "examples/policies/glasshouse/hostile_patrol.dtr",
        6_500,
        1_000,
        3,
        _capabilities(MOVE_TOWARD_CAPABILITY, WAIT_CAPABILITY),
    ),
    GlasshouseHostileLoadout(
        GlasshouseHostileRole.SENTRY,
        "examples/policies/glasshouse/hostile_sentry.dtr",
        4_000,
        0,
        4,
        _capabilities(AIM_CAPABILITY, WAIT_CAPABILITY),
    ),
    GlasshouseHostileLoadout(
        GlasshouseHostileRole.WARDEN,
        "examples/policies/glasshouse/hostile_warden.dtr",
        6_500,
        -1_000,
        5,
        _capabilities(WAIT_CAPABILITY),
    ),
)


def build_glasshouse_hostile_setup(
    players: GlasshousePlayerSetup, policy_sources: tuple[SourceFile, ...]
) -> GlasshouseHostileSetup | GlasshousePolicyFailure:
    """Compile and bind three project-authored hostile policies after player deployment."""
    if not isinstance(players, GlasshousePlayerSetup):
        raise TypeError("Glasshouse hostile setup requires the player setup")
    if not isinstance(policy_sources, tuple) or len(policy_sources) != len(
        GLASSHOUSE_HOSTILE_LOADOUTS
    ):
        raise ValueError("Glasshouse hostile setup requires three immutable policy sources")
    artifacts: list[CompiledArtifact] = []
    for source, loadout in zip(policy_sources, GLASSHOUSE_HOSTILE_LOADOUTS, strict=True):
        if not isinstance(source, SourceFile):
            raise TypeError("Glasshouse hostile policies must be source files")
        if source.file_id.value != loadout.policy_file_id:
            raise ValueError("Glasshouse hostile policy source IDs must match the canonical roster")
        compiled = _compile_policy(source)
        if isinstance(compiled, GlasshousePolicyFailure):
            return compiled
        artifacts.append(compiled)
    state = players.state
    weapons = list(state.weapons.entries)
    bindings = list(players.policy_bindings.entries)
    for loadout, artifact in zip(GLASSHOUSE_HOSTILE_LOADOUTS, artifacts, strict=True):
        state, entity = add_entity(
            state,
            WorldPosition(WorldSubunits(loadout.position_x), WorldSubunits(loadout.position_y)),
        )
        weapon_id, allocator = state.id_allocator.allocate_weapon()
        state = replace(state, id_allocator=allocator)
        weapons.append(
            EquippedWeapon(
                weapon_id,
                entity.entity_id,
                Ammunition(loadout.magazine_capacity, loadout.magazine_capacity),
            )
        )
        bindings.append(
            PolicyBinding(
                entity.entity_id,
                artifact,
                FunctionId(0),
                PLAYER_MEMORY_SCHEMA,
                RecordValue("Memory", ("label",), (StringValue(loadout.role.value),)),
                available_capabilities=loadout.capabilities,
            )
        )
    return GlasshouseHostileSetup(
        replace(state, weapons=WeaponStore(tuple(weapons))),
        PolicyBindings(tuple(bindings)),
    )


def _compile_policy(source: SourceFile) -> CompiledArtifact | GlasshousePolicyFailure:
    parsed = parse(lex(source))
    if parsed.diagnostics:
        return GlasshousePolicyFailure(source, parsed.diagnostics)
    checked = check(resolve(parsed.module))
    if checked.diagnostics:
        return GlasshousePolicyFailure(source, checked.diagnostics)
    if checked.module is None:
        raise AssertionError("successful policy check has no typed module")
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
