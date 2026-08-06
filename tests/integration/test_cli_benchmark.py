from __future__ import annotations

import re
import subprocess
import sys


def test_benchmark_cli_reports_five_headless_informational_measurements() -> None:
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "kiwi.cli",
            "benchmark",
            "examples/policies/typed_core.dtr",
            "tests/fixtures/minimal.kfixture.json",
            "--entry",
            "choose",
            "--arg",
            "true",
            "--iterations",
            "1",
            "--ticks",
            "1",
        ],
        capture_output=True,
        check=False,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert result.stderr == ""
    assert result.stdout.splitlines()[0] == "benchmark: informational; not a CI gate"
    assert tuple(line.split(":", maxsplit=1)[0] for line in result.stdout.splitlines()[1:]) == (
        "compiler",
        "vm",
        "tick",
        "trace",
        "replay_package",
    )
    assert all(
        re.fullmatch(r".+ operations=1 elapsed_ns=\d+ ns_per_operation=\d+\.\d{3}", line)
        for line in result.stdout.splitlines()[1:]
    )
