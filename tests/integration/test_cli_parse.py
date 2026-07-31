from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from kiwi.dsl.bytecode import BytecodeModule
from kiwi.dsl.bytecode_codec import decode_bytecode


def run_cli(command: str, path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "kiwi.cli", command, str(path)],
        capture_output=True,
        check=False,
        text=True,
    )


def run_cli_arguments(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "kiwi.cli", *arguments],
        capture_output=True,
        check=False,
        text=True,
    )


def test_parse_command_renders_stable_surface_ast(tmp_path: Path) -> None:
    path = tmp_path / "valid.dtr"
    path.write_text("fn id(x: Int) -> Int = x", encoding="utf-8")

    result = run_cli("parse", path)

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

    result = run_cli("parse", path)

    assert result.returncode == 1
    assert result.stdout == ""
    assert result.stderr == f"{path}:1:14: E201_EXPECTED_TOKEN: expected ':'\n"


def test_parse_command_reports_source_loading_failure(tmp_path: Path) -> None:
    path = tmp_path / "missing.dtr"

    result = run_cli("parse", path)

    assert result.returncode == 1
    assert result.stdout == ""
    assert result.stderr == f"{path}: S001_READ_FAILED: could not read source\n"


def test_check_command_renders_stable_core_output(tmp_path: Path) -> None:
    path = tmp_path / "valid.dtr"
    path.write_text("fn id(x: Int) -> Int = x", encoding="utf-8")

    result = run_cli("check", path)

    assert result.returncode == 0
    assert result.stderr == ""
    assert (
        result.stdout
        == f"""CoreModule span={str(path)!r}@0..24
  definitions:
    Definition id=0 symbol=0 kind=function name='id' type=Int -> Int span={str(path)!r}@0..24
      parameters:
        Parameter symbol=1 type=Int span={str(path)!r}@6..12
      body:
        Reference symbol=1 id=0 type=Int span={str(path)!r}@23..24
  source_map:
    Entry expression=0 definition=0 span={str(path)!r}@23..24
"""
    )


def test_check_command_reports_type_diagnostics(tmp_path: Path) -> None:
    path = tmp_path / "invalid.dtr"
    path.write_text("fn id(x: Int) -> Int = if x then 1 else 2", encoding="utf-8")

    result = run_cli("check", path)

    assert result.returncode == 1
    assert result.stdout == ""
    assert result.stderr == f"{path}:1:27: E401_TYPE_MISMATCH: expected Bool but received Int\n"


def test_compile_command_writes_canonical_bytecode(tmp_path: Path) -> None:
    source_path = tmp_path / "compile.dtr"
    output_path = tmp_path / "compile.kbc"
    source_path.write_text("fn id(x: Int) -> Int = x", encoding="utf-8")

    result = run_cli_arguments("compile", str(source_path), "--output", str(output_path))
    report = run_cli_arguments("compile", str(source_path))
    decoded = decode_bytecode(output_path.read_bytes())

    assert result.returncode == 0
    assert result.stderr == ""
    assert result.stdout == f"{output_path}: wrote {len(output_path.read_bytes())} bytes\n"
    assert isinstance(decoded, BytecodeModule)
    assert decoded.header.source_file_id.value == str(source_path)
    assert report.returncode == 0
    assert report.stdout == f"{source_path}: compiled {len(output_path.read_bytes())} bytes\n"
    assert report.stderr == ""


def test_disassemble_command_renders_compiled_source(tmp_path: Path) -> None:
    path = tmp_path / "disassemble.dtr"
    path.write_text("fn value() -> Int = -1", encoding="utf-8")

    result = run_cli_arguments("disassemble", str(path))

    assert result.returncode == 0
    assert result.stderr == ""
    assert (
        result.stdout
        == f"""BytecodeModule source={str(path)!r} language=2 core=2 bytecode=2
  constants:
    0: Integer(1)
  function_table:
    0: definition=0 name='value' arity=0
  functions:
    Function 0 definition=0 name='value' arity=0 locals=0 return=Int
      0000 TRACE_EXPRESSION 0
      0001 TRACE_EXPRESSION 1
      0002 PUSH_CONSTANT 0
      0003 NEGATE
      0004 RETURN
"""
    )


def test_run_policy_command_executes_explicit_arguments(tmp_path: Path) -> None:
    path = tmp_path / "policy.dtr"
    path.write_text(
        "policy choose(flag: Bool) -> Int = if flag then 1 else 2",
        encoding="utf-8",
    )

    success = run_cli_arguments("run-policy", str(path), "choose", "--arg", "true")
    invalid_argument = run_cli_arguments("run-policy", str(path), "choose", "--arg", "python")
    missing_entry = run_cli_arguments("run-policy", str(path), "missing")

    assert success.returncode == 0
    assert success.stdout == "value: Integer(1)\n"
    assert success.stderr == ""
    assert invalid_argument.returncode == 1
    assert invalid_argument.stdout == ""
    assert invalid_argument.stderr == (
        "run-policy: unsupported argument 'python'; use an integer, true, false, or unit\n"
    )
    assert missing_entry.returncode == 1
    assert missing_entry.stdout == ""
    assert missing_entry.stderr == f"{path}: R013_ENTRY: no function named 'missing'\n"


def test_run_policy_command_returns_string_and_exact_quantity_literals(tmp_path: Path) -> None:
    path = tmp_path / "literals.dtr"
    path.write_text(
        'policy label() -> String = "alpha"\npolicy wait() -> Duration = 250ms',
        encoding="utf-8",
    )

    label = run_cli_arguments("run-policy", str(path), "label")
    wait = run_cli_arguments("run-policy", str(path), "wait")

    assert label.returncode == 0
    assert label.stdout == "value: String('alpha')\n"
    assert label.stderr == ""
    assert wait.returncode == 0
    assert wait.stdout == "value: Quantity(Duration,1/4)\n"
    assert wait.stderr == ""


def test_run_policy_command_returns_canonically_ordered_record_fields(tmp_path: Path) -> None:
    path = tmp_path / "record.dtr"
    path.write_text(
        "type Point = { x: Int, y: Int }\npolicy origin() -> Point = Point { y = 2, x = 1 }",
        encoding="utf-8",
    )

    result = run_cli_arguments("run-policy", str(path), "origin")

    assert result.returncode == 0
    assert result.stdout == "value: Record(Point, {x=Integer(1), y=Integer(2)})\n"
    assert result.stderr == ""


def test_run_policy_command_returns_closed_option_values(tmp_path: Path) -> None:
    path = tmp_path / "option.dtr"
    path.write_text(
        "policy present() -> Option<Int> = Some(1)\npolicy absent() -> Option<Int> = None",
        encoding="utf-8",
    )

    present = run_cli_arguments("run-policy", str(path), "present")
    absent = run_cli_arguments("run-policy", str(path), "absent")

    assert present.returncode == 0
    assert present.stdout == "value: Some(Integer(1))\n"
    assert present.stderr == ""
    assert absent.returncode == 0
    assert absent.stdout == "value: None\n"
    assert absent.stderr == ""


def test_run_policy_command_executes_exhaustive_option_matches(tmp_path: Path) -> None:
    path = tmp_path / "matching.dtr"
    path.write_text(
        "policy choose() -> Int = match Some(1) with | Some(item) -> item | None -> 0",
        encoding="utf-8",
    )

    result = run_cli_arguments("run-policy", str(path), "choose")

    assert result.returncode == 0
    assert result.stdout == "value: Integer(1)\n"
    assert result.stderr == ""


def test_run_policy_command_returns_immutable_list_values(tmp_path: Path) -> None:
    path = tmp_path / "lists.dtr"
    path.write_text("policy values() -> List<Int> = [1, 2]", encoding="utf-8")

    result = run_cli_arguments("run-policy", str(path), "values")

    assert result.returncode == 0
    assert result.stdout == "value: List([Integer(1), Integer(2)])\n"
    assert result.stderr == ""


def test_run_policy_command_executes_anonymous_closure_calls(tmp_path: Path) -> None:
    path = tmp_path / "closures.dtr"
    path.write_text(
        "fn capture(seed: Int) -> Int -> Int = fn value -> seed\n"
        "policy execute() -> Int = capture(7)(0)",
        encoding="utf-8",
    )

    result = run_cli_arguments("run-policy", str(path), "execute")

    assert result.returncode == 0
    assert result.stdout == "value: Integer(7)\n"
    assert result.stderr == ""


def test_run_policy_command_executes_desugared_pipelines(tmp_path: Path) -> None:
    path = tmp_path / "pipeline.dtr"
    path.write_text(
        "fn first(input: Int, ignored: Int) -> Int = input\npolicy result() -> Int = 7 |> first(9)",
        encoding="utf-8",
    )

    result = run_cli_arguments("run-policy", str(path), "result")

    assert result.returncode == 0
    assert result.stdout == "value: Integer(7)\n"
    assert result.stderr == ""
