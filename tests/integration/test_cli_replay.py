from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from kiwi.replay.format import ReplayPacket, decode_replay, hash_replay


def test_replay_cli_records_verifies_inspects_and_compares_a_kernel_fixture(tmp_path: Path) -> None:
    fixture = tmp_path / "fixture.kfixture.json"
    replay = tmp_path / "run.drun"
    fixture.write_text(
        '{"format":"kiwi-kernel-fixture","version":1,"id":"minimal",'
        '"tick_rate":30,"seed":7,"entities":{"alpha":{"x":0,"y":0}},'
        '"scheduled_triggers":[]}',
        encoding="utf-8",
    )

    recorded = _run(
        "replay-record",
        str(fixture),
        "2",
        str(replay),
        "--application-build",
        "test-build",
        "--simulation-version",
        "sim-v1",
    )
    inspected = _run("replay-inspect", str(replay))
    verified = _run("replay-verify", str(replay))
    compared = _run("replay-compare", str(replay), str(replay))
    decoded = decode_replay(replay.read_bytes())

    assert recorded.returncode == 0
    assert recorded.stderr == ""
    assert recorded.stdout.startswith(f"{replay}: wrote ")
    assert isinstance(decoded, ReplayPacket)
    assert inspected.returncode == 0
    assert inspected.stdout == (
        "format: KWI-RUN v1\n"
        f"hash: {hash_replay(decoded).hex()}\n"
        "application_build: test-build\n"
        "simulation_version: sim-v1\n"
        f"mission_hash: {decoded.mission_hash.hex()}\n"
        "seed: 7\n"
        "tick_rate: 30\n"
        "commands: 0\n"
        "checkpoints: 3\n"
        "policy_versions: 0\n"
    )
    assert verified.returncode == 0
    assert verified.stdout == "verified: tick=2 checkpoints=3\n"
    assert compared.returncode == 0
    assert compared.stdout == "compatible: yes\n"


def test_replay_compare_reports_a_structured_baseline_mismatch(tmp_path: Path) -> None:
    fixture = tmp_path / "fixture.kfixture.json"
    first = tmp_path / "first.drun"
    second = tmp_path / "second.drun"
    fixture.write_text(
        '{"format":"kiwi-kernel-fixture","version":1,"id":"minimal",'
        '"tick_rate":30,"seed":7,"entities":{},"scheduled_triggers":[]}',
        encoding="utf-8",
    )
    for output, build in ((first, "first-build"), (second, "second-build")):
        result = _run(
            "replay-record",
            str(fixture),
            "1",
            str(output),
            "--application-build",
            build,
            "--simulation-version",
            "sim-v1",
        )
        assert result.returncode == 0

    compared = _run("replay-compare", str(first), str(second))

    assert compared.returncode == 1
    assert compared.stdout == (
        "compatible: no\nincompatible: RC001_APPLICATION_BUILD: application builds differ\n"
    )
    assert compared.stderr == ""


def test_replay_cli_uses_the_last_complete_backup_when_the_primary_is_corrupt(
    tmp_path: Path,
) -> None:
    fixture = tmp_path / "fixture.kfixture.json"
    replay = tmp_path / "run.drun"
    fixture.write_text(
        '{"format":"kiwi-kernel-fixture","version":1,"id":"minimal",'
        '"tick_rate":30,"seed":7,"entities":{},"scheduled_triggers":[]}',
        encoding="utf-8",
    )
    first = _run(
        "replay-record",
        str(fixture),
        "1",
        str(replay),
        "--application-build",
        "test-build",
        "--simulation-version",
        "sim-v1",
    )
    second = _run(
        "replay-record",
        str(fixture),
        "2",
        str(replay),
        "--application-build",
        "test-build",
        "--simulation-version",
        "sim-v1",
    )
    replay.write_bytes(b"corrupt")

    verified = _run("replay-verify", str(replay))

    assert first.returncode == 0
    assert second.returncode == 0
    assert replay.with_name("run.drun.bak").is_file()
    assert verified.returncode == 0
    assert verified.stdout == "verified: tick=1 checkpoints=2\n"
    assert verified.stderr == f"{replay}: recovered from {replay}.bak\n"


def _run(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "kiwi.cli", *arguments],
        capture_output=True,
        check=False,
        text=True,
    )
