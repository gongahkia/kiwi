"""Headless Glasshouse player-roster construction from bundled DSL policies."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.app.mission_loading import materialise_mission_state
from kiwi.content.missions import MissionData
from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EntityId, WeaponId
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.capabilities import (
    AIM_CAPABILITY,
    MOVE_TOWARD_CAPABILITY,
    TAKE_COVER_CAPABILITY,
    WAIT_CAPABILITY,
    CapabilityId,
)
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.diagnostics import Diagnostic
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import RecordValue, StringValue
from kiwi.dsl.source import SourceFile
from kiwi.dsl.types import BuiltinType
from kiwi.sim.objectives import ObjectiveStore, RetrievalObjective
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.state import MissionState, add_entity
from kiwi.sim.weapons import Ammunition, EquippedWeapon, WeaponStore


class GlasshousePlayerRole(StrEnum):
    """The four distinct initial player-facing squad roles."""

    BREACHER = "breacher"
    MEDIC = "medic"
    OVERWATCH = "overwatch"
    SCOUT = "scout"


@dataclass(frozen=True, slots=True)
class GlasshousePlayerLoadout:
    """One fixed initial player role, deployment position, and policy contract."""

    role: GlasshousePlayerRole
    callsign: str
    policy_file_id: str
    spawn: WorldPosition
    magazine_capacity: int
    capabilities: tuple[CapabilityId, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.role, GlasshousePlayerRole):
            raise ValueError("Glasshouse player loadout requires a role")
        if not isinstance(self.callsign, str) or not self.callsign:
            raise ValueError("Glasshouse player callsign must be text")
        if not isinstance(self.policy_file_id, str) or not self.policy_file_id:
            raise ValueError("Glasshouse player policy file ID must be text")
        if not isinstance(self.spawn, WorldPosition):
            raise ValueError("Glasshouse player spawn must be a world position")
        if (
            not isinstance(self.magazine_capacity, int)
            or isinstance(self.magazine_capacity, bool)
            or self.magazine_capacity <= 0
        ):
            raise ValueError("Glasshouse player magazine capacity must be positive")
        if not isinstance(self.capabilities, tuple):
            raise ValueError("Glasshouse player capabilities must be immutable")
        names = tuple(capability.value for capability in self.capabilities)
        if names != tuple(sorted(names)) or len(set(names)) != len(names):
            raise ValueError("Glasshouse player capabilities must be lexically ordered and unique")


@dataclass(frozen=True, slots=True)
class GlasshousePlayer:
    """One deployed player role with its allocated authority identities."""

    loadout: GlasshousePlayerLoadout
    entity_id: EntityId
    weapon_id: WeaponId

    def __post_init__(self) -> None:
        if not isinstance(self.loadout, GlasshousePlayerLoadout):
            raise ValueError("Glasshouse player requires a loadout")
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("Glasshouse player requires an entity ID")
        if not isinstance(self.weapon_id, WeaponId):
            raise ValueError("Glasshouse player requires a weapon ID")


@dataclass(frozen=True, slots=True)
class GlasshousePlayerSetup:
    """One prepared player roster, authority state, and entity-ID-ordered policy bindings."""

    state: MissionState
    players: tuple[GlasshousePlayer, ...]
    policy_bindings: PolicyBindings

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("Glasshouse player setup requires mission state")
        if not isinstance(self.players, tuple) or len(self.players) != 4:
            raise ValueError("Glasshouse player setup requires four immutable players")
        if not isinstance(self.policy_bindings, PolicyBindings):
            raise ValueError("Glasshouse player setup requires policy bindings")
        entity_ids = tuple(player.entity_id for player in self.players)
        if entity_ids != tuple(sorted(entity_ids, key=lambda entity_id: entity_id.value)):
            raise ValueError("Glasshouse players must be entity-ID ordered")
        if tuple(binding.entity_id for binding in self.policy_bindings.entries) != entity_ids:
            raise ValueError("Glasshouse player bindings must match the deployed roster")


@dataclass(frozen=True, slots=True)
class GlasshousePolicyFailure:
    """A structured diagnostic result while compiling one bundled player policy."""

    source: SourceFile
    diagnostics: tuple[Diagnostic, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.source, SourceFile):
            raise ValueError("Glasshouse policy failure requires source")
        if not isinstance(self.diagnostics, tuple) or not self.diagnostics:
            raise ValueError("Glasshouse policy failure requires diagnostics")


type GlasshousePlayerSetupResult = GlasshousePlayerSetup | GlasshousePolicyFailure


PLAYER_MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))
GLASSHOUSE_LOCKDOWN_DELAY_SECONDS = 90


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def _capabilities(*capabilities: CapabilityId) -> tuple[CapabilityId, ...]:
    return tuple(sorted(capabilities, key=lambda capability: capability.value))


GLASSHOUSE_PLAYER_LOADOUTS = (
    GlasshousePlayerLoadout(
        GlasshousePlayerRole.BREACHER,
        "Breach",
        "examples/policies/glasshouse/breacher.dtr",
        _position(-6_200, 600),
        6,
        _capabilities(MOVE_TOWARD_CAPABILITY, TAKE_COVER_CAPABILITY, WAIT_CAPABILITY),
    ),
    GlasshousePlayerLoadout(
        GlasshousePlayerRole.MEDIC,
        "Mender",
        "examples/policies/glasshouse/medic.dtr",
        _position(-5_400, 600),
        2,
        _capabilities(MOVE_TOWARD_CAPABILITY, WAIT_CAPABILITY),
    ),
    GlasshousePlayerLoadout(
        GlasshousePlayerRole.OVERWATCH,
        "Scope",
        "examples/policies/glasshouse/overwatch.dtr",
        _position(-5_400, -600),
        4,
        _capabilities(AIM_CAPABILITY, WAIT_CAPABILITY),
    ),
    GlasshousePlayerLoadout(
        GlasshousePlayerRole.SCOUT,
        "Lark",
        "examples/policies/glasshouse/scout.dtr",
        _position(-6_200, -600),
        3,
        _capabilities(MOVE_TOWARD_CAPABILITY, WAIT_CAPABILITY),
    ),
)


def build_glasshouse_player_setup(
    mission: MissionData, policy_sources: tuple[SourceFile, ...]
) -> GlasshousePlayerSetupResult:
    """Compile and bind the four bundled player policies for a Glasshouse mission."""
    if not isinstance(mission, MissionData):
        raise TypeError("Glasshouse player setup requires mission data")
    if mission.mission_id != "glasshouse":
        raise ValueError("Glasshouse player setup requires the Glasshouse mission")
    if not isinstance(policy_sources, tuple) or len(policy_sources) != len(
        GLASSHOUSE_PLAYER_LOADOUTS
    ):
        raise ValueError("Glasshouse player setup requires four immutable policy sources")
    for source, loadout in zip(policy_sources, GLASSHOUSE_PLAYER_LOADOUTS, strict=True):
        if not isinstance(source, SourceFile):
            raise TypeError("Glasshouse player policies must be source files")
        if source.file_id.value != loadout.policy_file_id:
            raise ValueError("Glasshouse player policy source IDs must match the canonical roster")
    artifacts: list[CompiledArtifact] = []
    for source in policy_sources:
        compiled = _compile_policy(source)
        if isinstance(compiled, GlasshousePolicyFailure):
            return compiled
        artifacts.append(compiled)
    state = materialise_mission_state(mission)
    players: list[GlasshousePlayer] = []
    weapons: list[EquippedWeapon] = []
    bindings: list[PolicyBinding] = []
    for loadout, artifact in zip(GLASSHOUSE_PLAYER_LOADOUTS, artifacts, strict=True):
        state, entity = add_entity(state, loadout.spawn)
        weapon_id, allocator = state.id_allocator.allocate_weapon()
        state = replace(state, id_allocator=allocator)
        weapon = EquippedWeapon(
            weapon_id,
            entity.entity_id,
            Ammunition(loadout.magazine_capacity, loadout.magazine_capacity),
        )
        players.append(GlasshousePlayer(loadout, entity.entity_id, weapon_id))
        weapons.append(weapon)
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
    state = _configure_glasshouse_objective(
        replace(state, weapons=WeaponStore(tuple(weapons))), mission, tuple(players)
    )
    return GlasshousePlayerSetup(state, tuple(players), PolicyBindings(tuple(bindings)))


def _configure_glasshouse_objective(
    state: MissionState, mission: MissionData, players: tuple[GlasshousePlayer, ...]
) -> MissionState:
    objective_region = mission.region_for("objective_room")
    extraction_region = mission.region_for("extraction")
    if objective_region is None or extraction_region is None:
        raise ValueError("Glasshouse mission requires objective and extraction regions")
    objective_id, allocator = state.id_allocator.allocate_objective()
    objective = RetrievalObjective(
        objective_id,
        objective_region.bounds,
        extraction_region.bounds,
        tuple(player.entity_id for player in players),
    )
    _, scheduled_events = state.scheduled_events.schedule(
        mission.tick_rate * GLASSHOUSE_LOCKDOWN_DELAY_SECONDS,
        ScheduledEventKind.LOCKDOWN,
    )
    return replace(
        state,
        id_allocator=allocator,
        objectives=ObjectiveStore((objective,)),
        scheduled_events=scheduled_events,
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
