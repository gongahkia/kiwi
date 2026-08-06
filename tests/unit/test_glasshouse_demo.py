from __future__ import annotations

from kiwi.app.glasshouse_demo import GlasshouseDemoController, GlasshouseDemoScreen
from kiwi.trace.comparison import ConsequenceDifferenceKind
from kiwi.ui.glasshouse_debrief import GlasshouseDebrief, GlasshouseDebriefUnavailable


def test_glasshouse_demo_runs_the_injury_to_revision_to_comparison_loop() -> None:
    baseline = GlasshouseDemoController.create().open_workbench().deploy()

    assert baseline.screen is GlasshouseDemoScreen.MISSION
    assert baseline.current_run is not None
    assert isinstance(baseline.current_run.debrief, GlasshouseDebrief)

    focused = baseline.open_debrief().guide_revision()

    assert focused.screen is GlasshouseDemoScreen.WORKBENCH
    assert focused.workbench.selected_policy.role == "scout"
    assert focused.workbench.editor.selected_text.startswith("MoveToward")

    threshold = focused.select_scout_threshold()
    revised = threshold.replace_selected_editor(
        threshold.workbench.editor.insert_text("0m")
    ).deploy()

    assert revised.screen is GlasshouseDemoScreen.MISSION
    assert revised.current_run is not None
    assert isinstance(revised.current_run.debrief, GlasshouseDebriefUnavailable)
    assert revised.comparison is not None
    assert revised.comparison.compatibility.is_compatible
    assert revised.comparison.consequences is not None
    assert tuple(difference.kind for difference in revised.comparison.consequences.differences) == (
        ConsequenceDifferenceKind.REMOVED,
    )
    assert revised.open_debrief().screen is GlasshouseDemoScreen.COMPARISON


def test_glasshouse_demo_blocks_deployment_after_a_policy_compile_failure() -> None:
    opened = GlasshouseDemoController.create().open_workbench()
    broken = opened.replace_selected_editor(opened.workbench.editor.insert_text("@"))

    result = broken.deploy()

    assert result.screen is GlasshouseDemoScreen.WORKBENCH
    assert result.current_run is None
    assert result.workbench.compile_output is not None
    assert not result.workbench.compile_output.succeeded
    assert result.notice == "Deployment blocked: fix a policy compile failure."
