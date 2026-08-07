from __future__ import annotations

import sys
from pathlib import Path

from pytest import MonkeyPatch

from kiwi.app.terminal_demo import (
    TerminalColorScheme,
    TerminalDemoController,
    TerminalDemoScreen,
    TerminalInputMode,
    _content_root,
)
from kiwi.dsl.source import ByteOffset
from kiwi.trace.comparison import ConsequenceDifferenceKind
from kiwi.ui.editor import EditorState
from kiwi.ui.terminal_debrief import TerminalDebrief, TerminalDebriefUnavailable


def test_terminal_demo_runs_the_injury_to_revision_to_comparison_loop() -> None:
    baseline = TerminalDemoController.create().confirm_input_mode().open_live_preview()

    assert baseline.screen is TerminalDemoScreen.LIVE_PREVIEW
    assert baseline.current_run is not None
    assert isinstance(baseline.current_run.debrief, TerminalDebrief)
    assert tuple(snapshot.tick for snapshot in baseline.current_run.snapshots) == (0, 1, 2)
    assert baseline.preview_playing
    assert baseline.workbench.selected_policy.role == "scout"
    assert baseline.workbench.editor.selected_text == "1"
    assert len(baseline.result_history.results) == 1
    results = baseline.open_results()
    assert results.screen is TerminalDemoScreen.RESULTS
    assert results.result_history.results[-1].casualties == 1
    wrapped = baseline.advance_preview().advance_preview().advance_preview()
    assert wrapped.preview_snapshot_index == 0
    assert wrapped.workbench.editor.selected_text == "1"

    focused = baseline.open_debrief().guide_revision()

    assert focused.screen is TerminalDemoScreen.LIVE_PREVIEW
    assert focused.workbench.selected_policy.role == "scout"
    assert focused.workbench.editor.selected_text.startswith("MoveToward")

    threshold = focused.select_scout_threshold()
    revised = threshold.replace_selected_editor(threshold.workbench.editor.insert_text("0"))

    assert revised.screen is TerminalDemoScreen.LIVE_PREVIEW
    assert revised.current_run is not None
    assert isinstance(revised.current_run.debrief, TerminalDebriefUnavailable)
    assert revised.comparison is not None
    assert revised.comparison.compatibility.is_compatible
    assert revised.comparison.consequences is not None
    assert tuple(difference.kind for difference in revised.comparison.consequences.differences) == (
        ConsequenceDifferenceKind.REMOVED,
    )
    assert revised.open_debrief().screen is TerminalDemoScreen.COMPARISON


def test_terminal_demo_hot_reloads_only_source_changes_into_recorded_preview_ticks() -> None:
    preview = TerminalDemoController.create().confirm_input_mode().open_live_preview()
    paused = preview.advance_preview().pause_preview()

    assert paused.preview_snapshot_index == 1
    assert not paused.preview_playing
    assert paused.workbench.selected_policy.role == "scout"

    focused = paused.select_scout_threshold()
    reloaded = focused.replace_selected_editor(focused.workbench.editor.insert_text("0"))

    assert reloaded.screen is TerminalDemoScreen.LIVE_PREVIEW
    assert reloaded.current_run is not None
    assert reloaded.preview_snapshot_index == 0
    assert reloaded.preview_playing
    assert isinstance(reloaded.current_run.debrief, TerminalDebriefUnavailable)

    traced = preview.select_policy_index(3).advance_preview()

    assert traced.preview_source_span() is not None
    assert traced.workbench.editor.selected_text


def test_terminal_demo_marks_preview_stale_when_hot_reload_is_disabled() -> None:
    preview = TerminalDemoController.create().confirm_input_mode().open_live_preview()
    disabled = preview.toggle_hot_reload()
    stale = disabled.replace_selected_editor(disabled.workbench.editor.insert_text(" "))

    assert not stale.hot_reload_enabled
    assert stale.preview_stale
    assert stale.current_run == preview.current_run
    assert stale.notice == "Preview out of date: Compile + run to refresh."


def test_terminal_demo_blocks_deployment_after_a_policy_compile_failure() -> None:
    opened = TerminalDemoController.create().confirm_input_mode().open_live_preview()
    broken = opened.replace_selected_editor(opened.workbench.editor.insert_text("@"))

    result = broken.deploy()

    assert result.screen is TerminalDemoScreen.LIVE_PREVIEW
    assert result.current_run is None
    assert result.workbench.compile_output is not None
    assert not result.workbench.compile_output.succeeded
    assert result.notice == "Deployment blocked: fix a policy compile failure."


def test_terminal_demo_detects_a_platform_default_and_requires_input_confirmation() -> None:
    controller = TerminalDemoController.create(platform_name="Darwin")

    assert controller.screen is TerminalDemoScreen.INPUT_SETUP
    assert controller.input_mode is TerminalInputMode.STANDARD
    assert controller.detected_platform == "Darwin"
    assert controller.open_live_preview() is controller

    function_keys = controller.choose_input_mode(TerminalInputMode.FUNCTION_KEYS)

    assert function_keys.input_mode is TerminalInputMode.FUNCTION_KEYS
    assert function_keys.confirm_input_mode().screen is TerminalDemoScreen.BRIEFING


def test_terminal_demo_cycles_theme_and_accepts_the_first_dsl_completion() -> None:
    opened = TerminalDemoController.create().confirm_input_mode().open_live_preview()
    typed = opened.replace_selected_editor(EditorState.from_text("Mov").move_cursor(3))

    assert typed.completions() == ("MoveToward",)
    assert typed.accept_completion().workbench.source.text == "MoveToward"

    amber = opened.cycle_color_scheme()

    assert amber.color_scheme is TerminalColorScheme.AMBER
    phosphor = amber.cycle_color_scheme()
    assert phosphor.color_scheme is TerminalColorScheme.PHOSPHOR
    assert phosphor.cycle_color_scheme().color_scheme is TerminalColorScheme.MAROON
    assert (
        phosphor.cycle_color_scheme().cycle_color_scheme().color_scheme is TerminalColorScheme.WHITE
    )
    assert (
        phosphor.cycle_color_scheme().cycle_color_scheme().cycle_color_scheme().color_scheme
        is TerminalColorScheme.BLACK
    )


def test_terminal_preview_maps_entities_and_source_offsets_to_retained_trace_steps() -> None:
    preview = TerminalDemoController.create().confirm_input_mode().open_live_preview()
    step = preview.advance_preview().pause_preview()

    from_map = step.select_preview_entity(1)
    span = from_map.preview_source_span()

    assert from_map.preview_selected_entity_id == 1
    assert from_map.selected_trace_node_id is not None
    assert span is not None
    from_source = from_map.select_preview_source_offset(ByteOffset(span.start.value))
    assert from_source.selected_trace_node_id is not None
    assert not from_source.preview_playing


def test_terminal_preview_rotation_is_presentation_only() -> None:
    preview = TerminalDemoController.create().confirm_input_mode().open_live_preview()
    rotated = preview.rotate_preview().rotate_preview()

    assert rotated.preview_rotation_quarters == 2
    assert rotated.current_run == preview.current_run
    assert rotated.workbench == preview.workbench


def test_terminal_preview_zoom_is_presentation_only_and_bounded() -> None:
    preview = TerminalDemoController.create().confirm_input_mode().open_live_preview()
    zoomed = preview.zoom_preview(1).zoom_preview(1)

    assert zoomed.preview_zoom_percent == 150
    assert zoomed.zoom_preview(1).preview_zoom_percent == 150
    assert zoomed.current_run == preview.current_run
    assert zoomed.workbench == preview.workbench


def test_terminal_preview_emits_one_presentation_feedback_pulse_for_an_impact() -> None:
    preview = TerminalDemoController.create().confirm_input_mode().open_live_preview()
    impact = preview.advance_preview().advance_preview()

    assert impact.preview_feedback_pulse == 1
    assert impact.current_run == preview.current_run


def test_terminal_content_root_uses_a_frozen_bundle_only_when_not_explicitly_supplied(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    bundled = tmp_path / "bundle"
    explicit = tmp_path / "explicit"
    monkeypatch.setattr(sys, "_MEIPASS", str(bundled), raising=False)

    assert _content_root(None) == bundled
    assert _content_root(explicit) == explicit
