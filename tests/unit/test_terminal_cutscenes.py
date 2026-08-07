from __future__ import annotations

from kiwi.ui.terminal_cutscenes import (
    TERMINAL_CUTSCENES,
    TerminalCutsceneBeatKind,
    terminal_cutscene,
)


def test_terminal_boot_cutscene_is_bounded_and_incremental() -> None:
    cutscene = terminal_cutscene("terminal_boot")

    initial = cutscene.visible_beats(1)
    complete = cutscene.visible_beats(cutscene.duration_milliseconds)

    assert initial == (cutscene.beats[0],)
    assert complete == cutscene.beats
    assert complete[-1].kind is TerminalCutsceneBeatKind.TRANSITION


def test_every_practice_level_intro_is_available_and_skippable() -> None:
    intro_ids = ("first_link_intro", "terminal_intro", "glasshouse_intro", "redline_intro")

    intros = tuple(terminal_cutscene(cutscene_id) for cutscene_id in intro_ids)

    assert all(cutscene.duration_milliseconds > 0 for cutscene in intros)
    assert {cutscene.cutscene_id for cutscene in intros}.issubset(
        {cutscene.cutscene_id for cutscene in TERMINAL_CUTSCENES}
    )
