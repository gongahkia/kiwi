from __future__ import annotations

from pathlib import Path

import pytest

from kiwi.app.glasshouse_execution import (
    GlasshouseMissionExecution,
    GlasshouseSignal,
    build_glasshouse_mission_execution,
    build_glasshouse_mission_presentation,
)
from kiwi.app.glasshouse_hostiles import GLASSHOUSE_HOSTILE_LOADOUTS
from kiwi.app.glasshouse_players import GLASSHOUSE_PLAYER_LOADOUTS
from kiwi.app.glasshouse_workbench import build_glasshouse_workbench
from kiwi.content.missions import MissionData, load_mission_file
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.sim.events import MissionStarted, SignalIssued
from kiwi.sim.signals import signals_for
from kiwi.sim.state import MissionPhase
from kiwi.ui.glasshouse_mission import GlasshouseMissionOutcome

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MISSION_PATH = REPOSITORY_ROOT / "examples" / "missions" / "glasshouse.dmission.json"


def _sources(file_ids: tuple[str, ...]) -> tuple[SourceFile, ...]:
    return tuple(
        SourceFile(SourceFileId(file_id), (REPOSITORY_ROOT / file_id).read_text(encoding="utf-8"))
        for file_id in file_ids
    )


def _execution() -> GlasshouseMissionExecution:
    mission = load_mission_file(MISSION_PATH)
    assert isinstance(mission, MissionData)
    workbench = build_glasshouse_workbench(
        _sources(tuple(loadout.policy_file_id for loadout in GLASSHOUSE_PLAYER_LOADOUTS))
    ).open_workbench()
    result = build_glasshouse_mission_execution(
        mission,
        workbench,
        _sources(tuple(loadout.policy_file_id for loadout in GLASSHOUSE_HOSTILE_LOADOUTS)),
    )
    assert isinstance(result, GlasshouseMissionExecution)
    return result


def test_glasshouse_execution_starts_and_applies_a_squad_signal_deterministically() -> None:
    first = _execution().request_start().advance().queue_signal(GlasshouseSignal.ADVANCE).advance()
    second = _execution().request_start().advance().queue_signal(GlasshouseSignal.ADVANCE).advance()

    assert first == second
    assert first.state.phase is MissionPhase.ACTIVE
    assert first.state.tick == 2
    assert isinstance(first.events[0], MissionStarted)
    assert isinstance(first.last_signal, SignalIssued)
    assert first.last_signal.command.signal.value == GlasshouseSignal.ADVANCE.value
    assert first.last_signal.command.target is None
    assert first.last_signal.command.header.tick == 1
    assert first.last_signal.command.header.sequence == 1
    assert isinstance(first.last_tick_events[0], SignalIssued)
    assert signals_for(first.state.signals, first.player_entity_ids[0], 1) == (
        first.state.signals.signals[0],
    )
    assert first.remaining_lockdown_ticks == first.lockdown_tick - first.state.tick
    presentation = build_glasshouse_mission_presentation(first)
    assert presentation.snapshot.tick == first.state.tick
    assert presentation.summary.outcome is GlasshouseMissionOutcome.IN_PROGRESS
    assert presentation.summary.panel_line == "MISSION: IN PROGRESS / objective active"
    assert presentation.signal_status is not None
    assert presentation.signal_status.panel_line == "LAST SIGNAL: advance / squad"


def test_glasshouse_execution_allows_only_player_targeted_signals() -> None:
    execution = _execution().request_start().advance()
    targeted = execution.queue_signal(
        GlasshouseSignal.HOLD, execution.player_entity_ids[-1]
    ).advance()
    hostile_entity_id = execution.state.entities[-1].entity_id

    assert isinstance(targeted.last_signal, SignalIssued)
    assert targeted.last_signal.command.signal.value == GlasshouseSignal.HOLD.value
    assert targeted.last_signal.command.target == execution.player_entity_ids[-1]
    with pytest.raises(ValueError, match="player operatives"):
        execution.queue_signal(GlasshouseSignal.HOLD, hostile_entity_id)
