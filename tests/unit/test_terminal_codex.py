from __future__ import annotations

from pathlib import Path

from kiwi.app.terminal_codex import (
    TerminalCodex,
    load_terminal_codex,
    load_terminal_codex_result,
    save_terminal_codex,
    terminal_lore_unlocks,
)
from kiwi.app.terminal_demo import TerminalDemoController


def test_policy_reached_shard_unlocks_and_persists(tmp_path: Path) -> None:
    preview = TerminalDemoController.create().confirm_input_mode().open_workbench().deploy()
    assert preview.current_run is not None

    unlocked = terminal_lore_unlocks(preview.current_run.snapshots[-1])
    codex = TerminalCodex().unlock(unlocked)
    path = tmp_path / "terminal_codex.json"
    save_terminal_codex(path, codex)

    assert codex.unlocked_ids == ("subnet_saltline",)
    assert load_terminal_codex(path) == codex


def test_terminal_codex_rejects_unknown_or_noncanonical_ids(tmp_path: Path) -> None:
    path = tmp_path / "terminal_codex.json"
    path.write_text(
        '{"format":"kiwi-terminal-codex","unlocked_ids":["unknown"],"version":1}',
        encoding="utf-8",
    )

    try:
        load_terminal_codex(path)
    except ValueError as error:
        assert "unavailable" in str(error)
    else:
        raise AssertionError("unknown lore IDs must be rejected")


def test_corrupt_codex_recovers_from_the_last_complete_backup(tmp_path: Path) -> None:
    path = tmp_path / "terminal_codex.json"
    first = TerminalCodex(("subnet_saltline",))

    assert save_terminal_codex(path, first).failure is None
    assert save_terminal_codex(path, TerminalCodex(("arasaka_blackice_note",))).failure is None
    path.write_text("{", encoding="utf-8")

    recovered = load_terminal_codex_result(path)

    assert recovered.codex == first
    assert recovered.failure is not None
    assert recovered.recovered_from_backup
    assert load_terminal_codex(path) == first
