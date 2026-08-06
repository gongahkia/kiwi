from __future__ import annotations

import pytest

from kiwi.sim.objectives import ObjectiveStatus
from kiwi.ui.terminal_mission import (
    TerminalMissionOutcome,
    build_terminal_mission_summary,
)


@pytest.mark.parametrize(
    ("objective_status", "lockdown_active", "outcome", "panel_line"),
    (
        (
            ObjectiveStatus.ACTIVE,
            False,
            TerminalMissionOutcome.IN_PROGRESS,
            "MISSION: IN PROGRESS / objective active",
        ),
        (
            ObjectiveStatus.RETRIEVED,
            True,
            TerminalMissionOutcome.FAILURE,
            "MISSION: FAILURE / lockdown blocked extraction",
        ),
        (
            ObjectiveStatus.EXTRACTED,
            True,
            TerminalMissionOutcome.SUCCESS,
            "MISSION: SUCCESS / objective extracted",
        ),
    ),
)
def test_terminal_mission_summary_projects_existing_terminal_facts(
    objective_status: ObjectiveStatus,
    lockdown_active: bool,
    outcome: TerminalMissionOutcome,
    panel_line: str,
) -> None:
    summary = build_terminal_mission_summary(
        objective_status,
        lockdown_active=lockdown_active,
    )

    assert summary.outcome is outcome
    assert summary.panel_line == panel_line


def test_terminal_mission_summary_rejects_non_authoritative_inputs() -> None:
    with pytest.raises(TypeError, match="objective status"):
        build_terminal_mission_summary("extracted", lockdown_active=False)  # type: ignore[arg-type]
    with pytest.raises(TypeError, match="must be boolean"):
        build_terminal_mission_summary(ObjectiveStatus.ACTIVE, lockdown_active=0)  # type: ignore[arg-type]
