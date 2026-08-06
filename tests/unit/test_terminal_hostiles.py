from __future__ import annotations

from pathlib import Path

from kiwi.app.terminal_hostiles import (
    TERMINAL_HOSTILE_LOADOUTS,
    TerminalHostileSetup,
    build_terminal_hostile_setup,
)
from kiwi.app.terminal_players import (
    TERMINAL_PLAYER_LOADOUTS,
    TerminalPlayerSetup,
    build_terminal_player_setup,
)
from kiwi.content.missions import MissionData, load_mission_file
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.events import IntentionEmitted, PolicyEvaluated
from kiwi.sim.runner import run_headless

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MISSION_PATH = REPOSITORY_ROOT / "examples" / "missions" / "terminal.dmission.json"


def _sources(file_ids: tuple[str, ...]) -> tuple[SourceFile, ...]:
    return tuple(
        SourceFile(
            SourceFileId(file_id),
            (REPOSITORY_ROOT / file_id).read_text(encoding="utf-8"),
        )
        for file_id in file_ids
    )


def test_terminal_hostiles_use_the_same_compiled_policy_boundary() -> None:
    mission = load_mission_file(MISSION_PATH)

    assert isinstance(mission, MissionData)
    players = build_terminal_player_setup(
        mission, _sources(tuple(loadout.policy_file_id for loadout in TERMINAL_PLAYER_LOADOUTS))
    )
    assert isinstance(players, TerminalPlayerSetup)
    setup = build_terminal_hostile_setup(
        players, _sources(tuple(loadout.policy_file_id for loadout in TERMINAL_HOSTILE_LOADOUTS))
    )

    assert isinstance(setup, TerminalHostileSetup)
    assert len(setup.state.entities) == len(setup.state.weapons.entries) == 7
    assert tuple(binding.entity_id for binding in setup.policy_bindings.entries) == tuple(
        entity.entity_id for entity in setup.state.entities
    )
    run = run_headless(
        setup.state,
        FixedTickClock(TickRate.HZ_30),
        1,
        (StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
        policy_bindings=setup.policy_bindings,
    )

    assert len(tuple(event for event in run.events if isinstance(event, PolicyEvaluated))) == 7
    assert len(tuple(event for event in run.events if isinstance(event, IntentionEmitted))) == 7
