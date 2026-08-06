from __future__ import annotations

from pathlib import Path

from kiwi.app.terminal_players import (
    TERMINAL_LOCKDOWN_DELAY_SECONDS,
    TERMINAL_PLAYER_LOADOUTS,
    TerminalPlayerRole,
    TerminalPlayerSetup,
    build_terminal_player_setup,
)
from kiwi.content.missions import MissionData, load_mission_file
from kiwi.domain.geometry import WorldSubunits
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.events import IntentionEmitted, IntentionSelected, PolicyEvaluated
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.objectives import ObjectiveStatus
from kiwi.sim.runner import run_headless
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.weapons import Ammunition

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MISSION_PATH = REPOSITORY_ROOT / "examples" / "missions" / "terminal.dmission.json"


def _policy_sources() -> tuple[SourceFile, ...]:
    return tuple(
        SourceFile(
            SourceFileId(loadout.policy_file_id),
            (REPOSITORY_ROOT / loadout.policy_file_id).read_text(encoding="utf-8"),
        )
        for loadout in TERMINAL_PLAYER_LOADOUTS
    )


def test_terminal_deploys_four_distinct_player_loadouts_and_policies() -> None:
    mission = load_mission_file(MISSION_PATH)

    assert isinstance(mission, MissionData)
    result = build_terminal_player_setup(mission, _policy_sources())

    assert isinstance(result, TerminalPlayerSetup)
    assert tuple(player.loadout.role.value for player in result.players) == (
        "breacher",
        "medic",
        "overwatch",
        "scout",
    )
    assert tuple(player.loadout.callsign for player in result.players) == (
        "Vector",
        "Patch",
        "Watch",
        "Lark",
    )
    assert tuple(entity.position for entity in result.state.entities) == tuple(
        loadout.spawn for loadout in TERMINAL_PLAYER_LOADOUTS
    )
    assert tuple(weapon.ammunition for weapon in result.state.weapons.entries) == tuple(
        Ammunition(loadout.magazine_capacity, loadout.magazine_capacity)
        for loadout in TERMINAL_PLAYER_LOADOUTS
    )
    assert tuple(
        binding.available_capabilities for binding in result.policy_bindings.entries
    ) == tuple(loadout.capabilities for loadout in TERMINAL_PLAYER_LOADOUTS)
    assert len(result.state.objectives.entries) == 1
    objective = result.state.objectives.entries[0]
    objective_region = mission.region_for("objective_room")
    extraction_region = mission.region_for("extraction")
    assert objective_region is not None
    assert extraction_region is not None
    assert objective.status is ObjectiveStatus.ACTIVE
    assert objective.required_entity_ids == tuple(player.entity_id for player in result.players)
    assert objective.retrieval_area == objective_region.bounds
    assert objective.extraction_area == extraction_region.bounds
    assert result.state.scheduled_events.pending[0].tick == (
        mission.tick_rate * TERMINAL_LOCKDOWN_DELAY_SECONDS
    )
    assert result.state.scheduled_events.pending[0].kind is ScheduledEventKind.LOCKDOWN
    assert len(result.state.contacts.estimates) == 1
    initial_contact = result.state.contacts.estimates[0]
    scout = next(
        player for player in result.players if player.loadout.role is TerminalPlayerRole.SCOUT
    )
    assert initial_contact.owner_entity_id == scout.entity_id
    assert initial_contact.uncertainty_radius == WorldSubunits(500)
    assert initial_contact.confidence.basis_points == 7_800


def test_terminal_player_policies_run_deterministically() -> None:
    mission = load_mission_file(MISSION_PATH)

    assert isinstance(mission, MissionData)
    setup = build_terminal_player_setup(mission, _policy_sources())
    assert isinstance(setup, TerminalPlayerSetup)
    command = StartMission(CommandHeader(0, 0, CommandSource.SCENARIO))
    first = run_headless(
        setup.state,
        FixedTickClock(TickRate.HZ_30),
        1,
        (command,),
        policy_bindings=setup.policy_bindings,
    )
    second = run_headless(
        setup.state,
        FixedTickClock(TickRate.HZ_30),
        1,
        (command,),
        policy_bindings=setup.policy_bindings,
    )

    assert first == second
    assert hash_canonical_state(first.state) == hash_canonical_state(second.state)
    assert len(tuple(event for event in first.events if isinstance(event, PolicyEvaluated))) == 4
    assert len(tuple(event for event in first.events if isinstance(event, IntentionEmitted))) == 4
    assert len(tuple(event for event in first.events if isinstance(event, IntentionSelected))) == 4
