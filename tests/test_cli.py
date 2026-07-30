from __future__ import annotations

import subprocess
import sys


def test_doctor_succeeds_headlessly() -> None:
    result = subprocess.run(
        [sys.executable, "-m", "kiwi.cli", "doctor"],
        capture_output=True,
        check=False,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout == "kiwi doctor: ok\npython: 3.12\npygame imported: no\n"


def test_importing_cli_does_not_import_pygame() -> None:
    result = subprocess.run(
        [sys.executable, "-c", "import sys; import kiwi.cli; assert 'pygame' not in sys.modules"],
        capture_output=True,
        check=False,
        text=True,
    )

    assert result.returncode == 0, result.stderr
