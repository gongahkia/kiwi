from __future__ import annotations

import os
from pathlib import Path

from pytest import MonkeyPatch

from kiwi.app.persistence import RecoverableWriteFailureCode, backup_path, write_recoverable_file


def test_recoverable_write_retains_the_previous_complete_file(tmp_path: Path) -> None:
    path = tmp_path / "local.json"

    assert write_recoverable_file(path, b"first") is None
    assert write_recoverable_file(path, b"second") is None

    assert path.read_bytes() == b"second"
    assert backup_path(path).read_bytes() == b"first"


def test_recoverable_write_keeps_a_complete_backup_if_primary_replacement_fails(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    path = tmp_path / "local.json"
    assert write_recoverable_file(path, b"first") is None
    original_replace = os.replace
    calls = 0

    def fail_primary_replace(source: Path | str, target: Path | str) -> None:
        nonlocal calls
        calls += 1
        if calls == 2:
            raise OSError("injected replace failure")
        original_replace(source, target)

    monkeypatch.setattr("kiwi.app.persistence.os.replace", fail_primary_replace)

    result = write_recoverable_file(path, b"second")

    assert result is not None
    assert result.code is RecoverableWriteFailureCode.REPLACE_PRIMARY
    assert not path.exists()
    assert backup_path(path).read_bytes() == b"first"
