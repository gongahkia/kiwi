from __future__ import annotations

from pathlib import Path

from kiwi.app.terminal_players import TERMINAL_PLAYER_LOADOUTS
from kiwi.app.terminal_workbench import build_terminal_workbench
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.ui.terminal_workbench import TerminalFlowPhase

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def _policy_sources() -> tuple[SourceFile, ...]:
    return tuple(
        SourceFile(
            SourceFileId(loadout.policy_file_id),
            (REPOSITORY_ROOT / loadout.policy_file_id).read_text(encoding="utf-8"),
        )
        for loadout in TERMINAL_PLAYER_LOADOUTS
    )


def test_terminal_briefing_opens_role_specific_workbench_and_compiles_selected_source() -> None:
    briefing = build_terminal_workbench(_policy_sources())

    assert briefing.phase is TerminalFlowPhase.BRIEFING
    assert briefing.briefing.panel_lines == (
        "KIWI // HOSTILE MAINFRAME",
        "",
        "PRIMARY OBJECTIVE",
        "Route daemons to the encrypted payload, then exfiltrate the bundle.",
        "",
        "TIME PRESSURE",
        "Trace containment seals the route exactly 90 seconds after deployment.",
        "",
        "INTELLIGENCE",
        "Hostile ICE telemetry is incomplete.",
        "Lark begins with one 0.5m-uncertainty ICE contact.",
        "Review each daemon policy before jacking in.",
        "",
        "OPEN KIWI WORKBENCH",
    )

    workbench = briefing.open_workbench().select_policy("scout").compile_selected()

    assert workbench.phase is TerminalFlowPhase.WORKBENCH
    assert tuple(policy.label for policy in workbench.policies) == (
        "Vector / daemon",
        "Patch / daemon",
        "Watch / daemon",
        "Lark / daemon",
    )
    assert workbench.selected_policy.label == "Lark / daemon"
    assert workbench.source.text == _policy_sources()[3].text
    assert workbench.compile_output is not None
    assert workbench.compile_output.succeeded


def test_terminal_workbench_keeps_editors_independent_and_invalidates_only_changed_output() -> None:
    workbench = build_terminal_workbench(_policy_sources()).open_workbench()
    compiled_breacher = workbench.compile_selected()
    edited_breacher = compiled_breacher.replace_editor(compiled_breacher.editor.insert_text("@"))
    failed_breacher = edited_breacher.compile_selected()
    scout = failed_breacher.select_policy("scout")

    assert compiled_breacher.compile_output is not None
    assert compiled_breacher.compile_output.succeeded
    assert edited_breacher.compile_output is None
    assert failed_breacher.compile_output is not None
    assert not failed_breacher.compile_output.succeeded
    assert scout.compile_output is None
    assert scout.source.text == _policy_sources()[3].text
