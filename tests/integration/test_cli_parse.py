from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def run_parse(path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "kiwi.cli", "parse", str(path)],
        capture_output=True,
        check=False,
        text=True,
    )


def test_parse_command_renders_stable_surface_ast(tmp_path: Path) -> None:
    path = tmp_path / "valid.dtr"
    path.write_text("fn id(x: Int) -> Int = x", encoding="utf-8")

    result = run_parse(path)

    assert result.returncode == 0
    assert result.stderr == ""
    assert (
        result.stdout
        == f"""SurfaceModule span={str(path)!r}@0..24
  declarations:
    FunctionDeclaration span={str(path)!r}@0..24
      name:
        Identifier text='id' span={str(path)!r}@3..5
      parameters:
        Parameter span={str(path)!r}@6..12
          name:
            Identifier text='x' span={str(path)!r}@6..7
          annotation:
            TypeReference span={str(path)!r}@9..12
              name:
                Identifier text='Int' span={str(path)!r}@9..12
      return_annotation:
        TypeReference span={str(path)!r}@17..20
          name:
            Identifier text='Int' span={str(path)!r}@17..20
      body:
        NameExpression span={str(path)!r}@23..24
          name:
            Identifier text='x' span={str(path)!r}@23..24
"""
    )


def test_parse_command_renders_structured_diagnostics(tmp_path: Path) -> None:
    path = tmp_path / "invalid.dtr"
    path.write_text("policy bad(x Int) -> Int = x", encoding="utf-8")

    result = run_parse(path)

    assert result.returncode == 1
    assert result.stdout == ""
    assert result.stderr == f"{path}:1:14: E201_EXPECTED_TOKEN: expected ':'\n"


def test_parse_command_reports_source_loading_failure(tmp_path: Path) -> None:
    path = tmp_path / "missing.dtr"

    result = run_parse(path)

    assert result.returncode == 1
    assert result.stdout == ""
    assert result.stderr == f"{path}: S001_READ_FAILED: could not read source\n"
