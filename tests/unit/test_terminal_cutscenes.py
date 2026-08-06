from __future__ import annotations

from kiwi.ui.terminal_cutscenes import TerminalCutsceneBeatKind, terminal_cutscene


def test_terminal_boot_cutscene_is_bounded_and_incremental() -> None:
    cutscene = terminal_cutscene("terminal_boot")

    initial = cutscene.visible_beats(1)
    complete = cutscene.visible_beats(cutscene.duration_milliseconds)

    assert initial == (cutscene.beats[0],)
    assert complete == cutscene.beats
    assert complete[-1].kind is TerminalCutsceneBeatKind.TRANSITION
