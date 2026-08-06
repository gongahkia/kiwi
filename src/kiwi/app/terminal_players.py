"""Headless Terminal player-roster construction from bundled DSL policies."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.app.mission_loading import materialise_mission_state
from kiwi.content.missions import MissionData
from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
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
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactEstimate,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactStore,
)
from kiwi.sim.objectives import ObjectiveStore, RetrievalObjective
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.state import MissionState, add_entity
from kiwi.sim.weapons import Ammunition, EquippedWeapon, WeaponStore


class TerminalPlayerRole(StrEnum):
    """The four distinct initial player-facing squad roles."""

    BREACHER = "breacher"
    MEDIC = "medic"
    OVERWATCH = "overwatch"
    SCOUT = "scout"


@dataclass(frozen=True, slots=True)
class TerminalPlayerLoadout:
    """One fixed initial player role, deployment position, and policy contract."""

    role: TerminalPlayerRole
    callsign: str
    policy_file_id: str
    spawn: WorldPosition
    magazine_capacity: int
    capabilities: tuple[CapabilityId, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.role, TerminalPlayerRole):
            raise ValueError("Terminal player loadout requires a role")
        if not isinstance(self.callsign, str) or not self.callsign:
            raise ValueError("Terminal player callsign must be text")
        if not isinstance(self.policy_file_id, str) or not self.policy_file_id:
            raise ValueError("Terminal player policy file ID must be text")
        if not isinstance(self.spawn, WorldPosition):
            raise ValueError("Terminal player spawn must be a world position")
        if (
            not isinstance(self.magazine_capacity, int)
            or isinstance(self.magazine_capacity, bool)
            or self.magazine_capacity <= 0
        ):
            raise ValueError("Terminal player magazine capacity must be positive")
        if not isinstance(self.capabilities, tuple):
            raise ValueError("Terminal player capabilities must be immutable")
        names = tuple(capability.value for capability in self.capabilities)
        if names != tuple(sorted(names)) or len(set(names)) != len(names):
            raise ValueError("Terminal player capabilities must be lexically ordered and unique")


@dataclass(frozen=True, slots=True)
class TerminalPlayer:
    """One deployed player role with its allocated authority identities."""

    loadout: TerminalPlayerLoadout
    entity_id: EntityId
    weapon_id: WeaponId

    def __post_init__(self) -> None:
        if not isinstance(self.loadout, TerminalPlayerLoadout):
            raise ValueError("Terminal player requires a loadout")
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("Terminal player requires an entity ID")
        if not isinstance(self.weapon_id, WeaponId):
            raise ValueError("Terminal player requires a weapon ID")


@dataclass(frozen=True, slots=True)
class TerminalPlayerSetup:
    """One prepared player roster, authority state, and entity-ID-ordered policy bindings."""

    state: MissionState
    players: tuple[TerminalPlayer, ...]
    policy_bindings: PolicyBindings

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("Terminal player setup requires mission state")
        if not isinstance(self.players, tuple) or len(self.players) != 4:
            raise ValueError("Terminal player setup requires four immutable players")
        if not isinstance(self.policy_bindings, PolicyBindings):
            raise ValueError("Terminal player setup requires policy bindings")
        entity_ids = tuple(player.entity_id for player in self.players)
        if entity_ids != tuple(sorted(entity_ids, key=lambda entity_id: entity_id.value)):
            raise ValueError("Terminal players must be entity-ID ordered")
        if tuple(binding.entity_id for binding in self.policy_bindings.entries) != entity_ids:
            raise ValueError("Terminal player bindings must match the deployed roster")


@dataclass(frozen=True, slots=True)
class TerminalPolicyFailure:
    """A structured diagnostic result while compiling one bundled player policy."""

    source: SourceFile
    diagnostics: tuple[Diagnostic, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.source, SourceFile):
            raise ValueError("Terminal policy failure requires source")
        if not isinstance(self.diagnostics, tuple) or not self.diagnostics:
            raise ValueError("Terminal policy failure requires diagnostics")


type TerminalPlayerSetupResult = TerminalPlayerSetup | TerminalPolicyFailure


PLAYER_MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))
TERMINAL_LOCKDOWN_DELAY_SECONDS = 90


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def _capabilities(*capabilities: CapabilityId) -> tuple[CapabilityId, ...]:
    return tuple(sorted(capabilities, key=lambda capability: capability.value))


TERMINAL_PLAYER_LOADOUTS = (
    TerminalPlayerLoadout(
        TerminalPlayerRole.BREACHER,
        "Breach",
        "examples/policies/terminal/breacher.dtr",
        _position(-6_200, 600),
        6,
        _capabilities(MOVE_TOWARD_CAPABILITY, TAKE_COVER_CAPABILITY, WAIT_CAPABILITY),
    ),
    TerminalPlayerLoadout(
        TerminalPlayerRole.MEDIC,
        "Mender",
        "examples/policies/terminal/medic.dtr",
        _position(-5_400, 600),
        2,
        _capabilities(MOVE_TOWARD_CAPABILITY, WAIT_CAPABILITY),
    ),
    TerminalPlayerLoadout(
        TerminalPlayerRole.OVERWATCH,
        "Scope",
        "examples/policies/terminal/overwatch.dtr",
        _position(-5_400, -600),
        4,
        _capabilities(AIM_CAPABILITY, WAIT_CAPABILITY),
    ),
    TerminalPlayerLoadout(
        TerminalPlayerRole.SCOUT,
        "Lark",
        "examples/policies/terminal/scout.dtr",
        _position(-6_200, -600),
        3,
        _capabilities(MOVE_TOWARD_CAPABILITY, WAIT_CAPABILITY),
    ),
)


def build_terminal_player_setup(
    mission: MissionData, policy_sources: tuple[SourceFile, ...]
) -> TerminalPlayerSetupResult:
    """Compile and bind the four bundled player policies for a Terminal mission."""
    if not isinstance(mission, MissionData):
        raise TypeError("Terminal player setup requires mission data")
    if mission.mission_id != "terminal":
        raise ValueError("Terminal player setup requires the Terminal mission")
    if not isinstance(policy_sources, tuple) or len(policy_sources) != len(
        TERMINAL_PLAYER_LOADOUTS
    ):
        raise ValueError("Terminal player setup requires four immutable policy sources")
    for source, loadout in zip(policy_sources, TERMINAL_PLAYER_LOADOUTS, strict=True):
        if not isinstance(source, SourceFile):
            raise TypeError("Terminal player policies must be source files")
        if source.file_id.value != loadout.policy_file_id:
            raise ValueError("Terminal player policy source IDs must match the canonical roster")
    artifacts: list[CompiledArtifact] = []
    for source in policy_sources:
        compiled = _compile_policy(source)
        if isinstance(compiled, TerminalPolicyFailure):
            return compiled
        artifacts.append(compiled)
    state = materialise_mission_state(mission)
    players: list[TerminalPlayer] = []
    weapons: list[EquippedWeapon] = []
    bindings: list[PolicyBinding] = []
    for loadout, artifact in zip(TERMINAL_PLAYER_LOADOUTS, artifacts, strict=True):
        state, entity = add_entity(state, loadout.spawn)
        weapon_id, allocator = state.id_allocator.allocate_weapon()
        state = replace(state, id_allocator=allocator)
        weapon = EquippedWeapon(
            weapon_id,
            entity.entity_id,
            Ammunition(loadout.magazine_capacity, loadout.magazine_capacity),
        )
        players.append(TerminalPlayer(loadout, entity.entity_id, weapon_id))
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
    state = _configure_terminal_objective(
        replace(state, weapons=WeaponStore(tuple(weapons))), mission, tuple(players)
    )
    return TerminalPlayerSetup(state, tuple(players), PolicyBindings(tuple(bindings)))


def _configure_terminal_objective(
    state: MissionState, mission: MissionData, players: tuple[TerminalPlayer, ...]
) -> MissionState:
    objective_region = mission.region_for("objective_room")
    extraction_region = mission.region_for("extraction")
    if objective_region is None or extraction_region is None:
        raise ValueError("Terminal mission requires objective and extraction regions")
    objective_id, allocator = state.id_allocator.allocate_objective()
    objective = RetrievalObjective(
        objective_id,
        objective_region.bounds,
        extraction_region.bounds,
        tuple(player.entity_id for player in players),
    )
    _, scheduled_events = state.scheduled_events.schedule(
        mission.tick_rate * TERMINAL_LOCKDOWN_DELAY_SECONDS,
        ScheduledEventKind.LOCKDOWN,
    )
    state = replace(
        state,
        id_allocator=allocator,
        objectives=ObjectiveStore((objective,)),
        scheduled_events=scheduled_events,
    )
    return _configure_flawed_scout_contact(state, players, objective_region.bounds)


def _configure_flawed_scout_contact(
    state: MissionState,
    players: tuple[TerminalPlayer, ...],
    objective_area: WorldRectangle,
) -> MissionState:
    scouts = tuple(
        player for player in players if player.loadout.role is TerminalPlayerRole.SCOUT
    )
    if len(scouts) != 1:
        raise AssertionError("Terminal roster requires exactly one scout")
    scout = scouts[0]
    evidence_event_id, allocator = state.id_allocator.allocate_event()
    contact_id, allocator = allocator.allocate_contact()
    estimated_position = WorldPosition(
        WorldSubunits((objective_area.minimum_x.value + objective_area.maximum_x.value) // 2),
        WorldSubunits((objective_area.minimum_y.value + objective_area.maximum_y.value) // 2),
    )
    provenance = ContactProvenance(
        tuple(ContactFieldProvenance(field, (evidence_event_id,)) for field in ContactField)
    )
    return replace(
        state,
        id_allocator=allocator,
        contacts=ContactStore(
            (
                ContactEstimate(
                    contact_id,
                    scout.entity_id,
                    estimated_position,
                    WorldSubunits(500),
                    ContactConfidence(7_800),
                    state.tick,
                    provenance,
                ),
            )
        ),
    )


def _compile_policy(source: SourceFile) -> CompiledArtifact | TerminalPolicyFailure:
    parsed = parse(lex(source))
    if parsed.diagnostics:
        return TerminalPolicyFailure(source, parsed.diagnostics)
    checked = check(resolve(parsed.module))
    if checked.diagnostics:
        return TerminalPolicyFailure(source, checked.diagnostics)
    if checked.module is None:
        raise AssertionError("successful policy check has no typed module")
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
