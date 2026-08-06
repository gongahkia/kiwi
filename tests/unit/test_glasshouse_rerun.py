from __future__ import annotations

from dataclasses import replace
from pathlib import Path

from kiwi.app.glasshouse_execution import (
    GlasshouseMissionExecution,
    GlasshouseSignal,
    build_glasshouse_mission_execution,
)
from kiwi.app.glasshouse_hostiles import GLASSHOUSE_HOSTILE_LOADOUTS
from kiwi.app.glasshouse_players import GLASSHOUSE_PLAYER_LOADOUTS
from kiwi.app.glasshouse_rerun import (
    GlasshouseControlledComparison,
    GlasshouseReplayIdentity,
    GlasshouseRerunUnavailable,
    GlasshouseRerunUnavailableCode,
    controlled_glasshouse_rerun,
    record_glasshouse_execution,
)
from kiwi.app.glasshouse_workbench import build_glasshouse_workbench
from kiwi.content.missions import MissionData, load_mission_file
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.ui.glasshouse_workbench import GlasshouseWorkbench

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MISSION_PATH = REPOSITORY_ROOT / "examples" / "missions" / "glasshouse.dmission.json"
IDENTITY = GlasshouseReplayIdentity("test-build", "sim-v1", b"m" * 32)


def test_controlled_glasshouse_rerun_reuses_exact_inputs_and_compares_changed_policy() -> None:
    mission = _mission()
    baseline_execution = _execution(mission).request_start().advance()
    baseline_execution = baseline_execution.queue_signal(GlasshouseSignal.ADVANCE).advance()
    baseline = record_glasshouse_execution(baseline_execution, IDENTITY)
    workbench = _workbench().select_policy("scout")
    threshold = workbench.editor.buffer.text.index("1m")
    revised_workbench = workbench.replace_editor(
        workbench.editor.select(threshold, threshold + 2).insert_text("0m")
    )

    result = controlled_glasshouse_rerun(
        baseline,
        mission,
        revised_workbench,
        _sources(tuple(loadout.policy_file_id for loadout in GLASSHOUSE_HOSTILE_LOADOUTS)),
    )

    assert baseline.commands == baseline_execution.command_log
    assert baseline.recorded.run.state == baseline_execution.state
    assert isinstance(result, GlasshouseControlledComparison)
    assert result.rerun.commands == baseline.commands
    assert result.rerun.recorded.replay.seed == baseline.recorded.replay.seed
    assert result.comparison.compatibility.is_compatible
    assert result.comparison.compatibility.policy_differences


def test_controlled_glasshouse_rerun_rejects_a_changed_initial_state() -> None:
    mission = _mission()
    baseline_execution = _execution(mission).request_start().advance()
    baseline = record_glasshouse_execution(baseline_execution, IDENTITY)

    result = controlled_glasshouse_rerun(
        baseline,
        replace(mission, seed=mission.seed + 1),
        _workbench(),
        _sources(tuple(loadout.policy_file_id for loadout in GLASSHOUSE_HOSTILE_LOADOUTS)),
    )

    assert isinstance(result, GlasshouseRerunUnavailable)
    assert result.code is GlasshouseRerunUnavailableCode.INITIAL_STATE_CHANGED


def _mission() -> MissionData:
    mission = load_mission_file(MISSION_PATH)
    assert isinstance(mission, MissionData)
    return mission


def _execution(mission: MissionData) -> GlasshouseMissionExecution:
    result = build_glasshouse_mission_execution(
        mission,
        _workbench(),
        _sources(tuple(loadout.policy_file_id for loadout in GLASSHOUSE_HOSTILE_LOADOUTS)),
    )
    assert isinstance(result, GlasshouseMissionExecution)
    return result


def _workbench() -> GlasshouseWorkbench:
    return build_glasshouse_workbench(
        _sources(tuple(loadout.policy_file_id for loadout in GLASSHOUSE_PLAYER_LOADOUTS))
    ).open_workbench()


def _sources(file_ids: tuple[str, ...]) -> tuple[SourceFile, ...]:
    return tuple(
        SourceFile(SourceFileId(file_id), (REPOSITORY_ROOT / file_id).read_text(encoding="utf-8"))
        for file_id in file_ids
    )
