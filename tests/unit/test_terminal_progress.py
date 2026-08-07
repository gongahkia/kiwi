from __future__ import annotations

from pathlib import Path

from kiwi.app.terminal_progress import (
    TerminalProgress,
    load_terminal_progress,
    save_terminal_progress,
)


def test_terminal_progress_round_trips_and_rejects_invalid_local_data(tmp_path: Path) -> None:
    path = tmp_path / "terminal_progress.json"

    assert load_terminal_progress(path) == TerminalProgress()

    save_terminal_progress(path, TerminalProgress().complete_onboarding())

    assert load_terminal_progress(path) == TerminalProgress(True)
    path.write_text('{"format":"wrong","version":1,"onboarding_complete":true}', encoding="utf-8")
    assert load_terminal_progress(path) == TerminalProgress()
