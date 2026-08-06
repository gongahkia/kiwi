from __future__ import annotations

from dataclasses import replace
from pathlib import Path

from kiwi.app.terminal_execution import (
    TerminalMissionExecution,
    TerminalSignal,
    build_terminal_mission_execution,
)
from kiwi.app.terminal_hostiles import TERMINAL_HOSTILE_LOADOUTS
from kiwi.app.terminal_players import TERMINAL_PLAYER_LOADOUTS
from kiwi.app.terminal_rerun import (
    TerminalControlledComparison,
    TerminalReplayIdentity,
    TerminalRerunUnavailable,
    TerminalRerunUnavailableCode,
    controlled_terminal_rerun,
    record_terminal_execution,
)
from kiwi.app.terminal_workbench import build_terminal_workbench
from kiwi.content.missions import MissionData, load_mission_file
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.ui.terminal_workbench import TerminalWorkbench

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MISSION_PATH = REPOSITORY_ROOT / "examples" / "missions" / "terminal.dmission.json"
IDENTITY = TerminalReplayIdentity("test-build", "sim-v1", b"m" * 32)


def test_controlled_terminal_rerun_reuses_exact_inputs_and_compares_changed_policy() -> None:
    mission = _mission()
    baseline_execution = _execution(mission).request_start().advance()
    baseline_execution = baseline_execution.queue_signal(TerminalSignal.ADVANCE).advance()
    baseline = record_terminal_execution(baseline_execution, IDENTITY)
    workbench = _workbench().select_policy("scout")
    threshold = workbench.editor.buffer.text.index("1m")
    revised_workbench = workbench.replace_editor(
        workbench.editor.select(threshold, threshold + 2).insert_text("0m")
    )

    result = controlled_terminal_rerun(
        baseline,
        mission,
        revised_workbench,
        _sources(tuple(loadout.policy_file_id for loadout in TERMINAL_HOSTILE_LOADOUTS)),
    )

    assert baseline.commands == baseline_execution.command_log
    assert baseline.recorded.run.state == baseline_execution.state
    assert isinstance(result, TerminalControlledComparison)
    assert result.rerun.commands == baseline.commands
    assert result.rerun.recorded.replay.seed == baseline.recorded.replay.seed
    assert result.comparison.compatibility.is_compatible
    assert result.comparison.compatibility.policy_differences


def test_controlled_terminal_rerun_rejects_a_changed_initial_state() -> None:
    mission = _mission()
    baseline_execution = _execution(mission).request_start().advance()
    baseline = record_terminal_execution(baseline_execution, IDENTITY)

    result = controlled_terminal_rerun(
        baseline,
        replace(mission, seed=mission.seed + 1),
        _workbench(),
        _sources(tuple(loadout.policy_file_id for loadout in TERMINAL_HOSTILE_LOADOUTS)),
    )

    assert isinstance(result, TerminalRerunUnavailable)
    assert result.code is TerminalRerunUnavailableCode.INITIAL_STATE_CHANGED


def _mission() -> MissionData:
    mission = load_mission_file(MISSION_PATH)
    assert isinstance(mission, MissionData)
    return mission


def _execution(mission: MissionData) -> TerminalMissionExecution:
    result = build_terminal_mission_execution(
        mission,
        _workbench(),
        _sources(tuple(loadout.policy_file_id for loadout in TERMINAL_HOSTILE_LOADOUTS)),
    )
    assert isinstance(result, TerminalMissionExecution)
    return result


def _workbench() -> TerminalWorkbench:
    return build_terminal_workbench(
        _sources(tuple(loadout.policy_file_id for loadout in TERMINAL_PLAYER_LOADOUTS))
    ).open_workbench()


def _sources(file_ids: tuple[str, ...]) -> tuple[SourceFile, ...]:
    return tuple(
        SourceFile(SourceFileId(file_id), (REPOSITORY_ROOT / file_id).read_text(encoding="utf-8"))
        for file_id in file_ids
    )
