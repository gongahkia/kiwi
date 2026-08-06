from __future__ import annotations

from kiwi.app.glasshouse_demo import (
    GlasshouseDemoController,
    GlasshouseDemoScreen,
    GlasshouseInputMode,
)
from kiwi.trace.comparison import ConsequenceDifferenceKind
from kiwi.ui.glasshouse_debrief import GlasshouseDebrief, GlasshouseDebriefUnavailable


def test_glasshouse_demo_runs_the_injury_to_revision_to_comparison_loop() -> None:
    baseline = GlasshouseDemoController.create().confirm_input_mode().open_workbench().deploy()

    assert baseline.screen is GlasshouseDemoScreen.LIVE_PREVIEW
    assert baseline.current_run is not None
    assert isinstance(baseline.current_run.debrief, GlasshouseDebrief)
    assert tuple(snapshot.tick for snapshot in baseline.current_run.snapshots) == (0, 1, 2)
    assert baseline.preview_playing
    assert baseline.workbench.selected_policy.role == "scout"
    assert baseline.workbench.editor.selected_text == "1"

    focused = baseline.open_debrief().guide_revision()

    assert focused.screen is GlasshouseDemoScreen.WORKBENCH
    assert focused.workbench.selected_policy.role == "scout"
    assert focused.workbench.editor.selected_text.startswith("MoveToward")

    threshold = focused.select_scout_threshold()
    revised = threshold.replace_selected_editor(
        threshold.workbench.editor.insert_text("0")
    ).deploy()

    assert revised.screen is GlasshouseDemoScreen.LIVE_PREVIEW
    assert revised.current_run is not None
    assert isinstance(revised.current_run.debrief, GlasshouseDebriefUnavailable)
    assert revised.comparison is not None
    assert revised.comparison.compatibility.is_compatible
    assert revised.comparison.consequences is not None
    assert tuple(difference.kind for difference in revised.comparison.consequences.differences) == (
        ConsequenceDifferenceKind.REMOVED,
    )
    assert revised.open_debrief().screen is GlasshouseDemoScreen.COMPARISON


def test_glasshouse_demo_hot_reloads_only_source_changes_into_recorded_preview_ticks() -> None:
    preview = GlasshouseDemoController.create().confirm_input_mode().open_workbench().deploy()
    paused = preview.advance_preview().pause_preview()

    assert paused.preview_snapshot_index == 1
    assert not paused.preview_playing
    assert paused.workbench.selected_policy.role == "scout"

    focused = paused.select_scout_threshold()
    reloaded = focused.replace_selected_editor(focused.workbench.editor.insert_text("0"))

    assert reloaded.screen is GlasshouseDemoScreen.LIVE_PREVIEW
    assert reloaded.current_run is not None
    assert reloaded.preview_snapshot_index == 0
    assert reloaded.preview_playing
    assert isinstance(reloaded.current_run.debrief, GlasshouseDebriefUnavailable)

    traced = preview.select_policy_index(3).advance_preview()

    assert traced.preview_source_span() is not None
    assert traced.workbench.editor.selected_text


def test_glasshouse_demo_marks_preview_stale_when_hot_reload_is_disabled() -> None:
    preview = GlasshouseDemoController.create().confirm_input_mode().open_workbench().deploy()
    disabled = preview.toggle_hot_reload()
    stale = disabled.replace_selected_editor(disabled.workbench.editor.insert_text(" "))

    assert not stale.hot_reload_enabled
    assert stale.preview_stale
    assert stale.current_run == preview.current_run
    assert stale.notice == "Preview out of date: Compile + run to refresh."


def test_glasshouse_demo_blocks_deployment_after_a_policy_compile_failure() -> None:
    opened = GlasshouseDemoController.create().confirm_input_mode().open_workbench()
    broken = opened.replace_selected_editor(opened.workbench.editor.insert_text("@"))

    result = broken.deploy()

    assert result.screen is GlasshouseDemoScreen.WORKBENCH
    assert result.current_run is None
    assert result.workbench.compile_output is not None
    assert not result.workbench.compile_output.succeeded
    assert result.notice == "Deployment blocked: fix a policy compile failure."


def test_glasshouse_demo_detects_a_platform_default_and_requires_input_confirmation() -> None:
    controller = GlasshouseDemoController.create(platform_name="Darwin")

    assert controller.screen is GlasshouseDemoScreen.INPUT_SETUP
    assert controller.input_mode is GlasshouseInputMode.STANDARD
    assert controller.detected_platform == "Darwin"
    assert controller.open_workbench() is controller

    function_keys = controller.choose_input_mode(GlasshouseInputMode.FUNCTION_KEYS)

    assert function_keys.input_mode is GlasshouseInputMode.FUNCTION_KEYS
    assert function_keys.confirm_input_mode().screen is GlasshouseDemoScreen.BRIEFING
