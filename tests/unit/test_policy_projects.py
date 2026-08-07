from __future__ import annotations

from pathlib import Path

import pytest

from kiwi.content.projects import (
    POLICY_PROJECT_FORMAT,
    POLICY_PROJECT_VERSION,
    PolicyProject,
    PolicyProjectDiagnostic,
    PolicyProjectDiagnosticCode,
    PolicyProjectValidationFailure,
    validate_policy_project_file,
)
from kiwi.dsl.diagnostics import Diagnostic


def _write_project(root: Path, manifest: str, source: str) -> Path:
    source_path = root / "src" / "policy.dtr"
    source_path.parent.mkdir()
    source_path.write_text(source, encoding="utf-8")
    manifest_path = root / "kiwi.policy.json"
    manifest_path.write_text(manifest, encoding="utf-8")
    return manifest_path


def _manifest(reference: str, *, parameters: str | None = None) -> str:
    parameter_field = "" if parameters is None else f',"parameters":"{parameters}"'
    return (
        "{"
        f'"entry_points":{{"operative":"{reference}"}},'
        f'"format":"{POLICY_PROJECT_FORMAT}",'
        '"language_version":2,'
        '"name":"cautious-alpha"'
        f"{parameter_field},"
        f'"version":{POLICY_PROJECT_VERSION}'
        "}"
    )


_VALID_POLICY = """type Observation = { tick: Int }
type Memory = { label: String }
type Wait = { duration: Duration }
type Decision = { intentions: List<Wait>, memory: Memory }

policy hold(observation: Observation, memory: Memory) -> Decision =
  Decision { intentions = [Wait { duration = 1s }], memory = memory }
"""


def test_policy_project_validates_confined_sources_entries_and_parameters(tmp_path: Path) -> None:
    (tmp_path / "parameters.json").write_text("{}", encoding="utf-8")
    manifest_path = _write_project(
        tmp_path,
        _manifest("src/policy.dtr#hold", parameters="parameters.json"),
        _VALID_POLICY,
    )

    result = validate_policy_project_file(manifest_path)

    assert isinstance(result, PolicyProject)
    assert result.root == tmp_path.resolve()
    assert result.name == "cautious-alpha"
    assert result.entries[0].name == "operative"
    assert result.entries[0].source_path.as_posix() == "src/policy.dtr"
    assert result.entries[0].function_name == "hold"
    assert result.parameters_path is not None
    assert result.parameters_path.as_posix() == "parameters.json"


def test_policy_project_rejects_source_paths_that_escape_the_project_root(tmp_path: Path) -> None:
    manifest_path = _write_project(tmp_path, _manifest("../outside.dtr#hold"), _VALID_POLICY)

    result = validate_policy_project_file(manifest_path)

    assert isinstance(result, PolicyProjectValidationFailure)
    issue = result.issues[0]
    assert isinstance(issue, PolicyProjectDiagnostic)
    assert issue.code == PolicyProjectDiagnosticCode.INVALID_PATH.value
    assert issue.path == "$.entry_points.operative"


def test_policy_project_rejects_symlinked_sources_that_escape_the_project_root(
    tmp_path: Path,
) -> None:
    outside = tmp_path.parent / f"{tmp_path.name}-outside.dtr"
    outside.write_text(_VALID_POLICY, encoding="utf-8")
    linked = tmp_path / "linked.dtr"
    try:
        linked.symlink_to(outside)
    except OSError:
        pytest.skip("the test host cannot create a symlink")
    manifest_path = tmp_path / "kiwi.policy.json"
    manifest_path.write_text(_manifest("linked.dtr#hold"), encoding="utf-8")

    result = validate_policy_project_file(manifest_path)

    assert isinstance(result, PolicyProjectValidationFailure)
    issue = result.issues[0]
    assert isinstance(issue, PolicyProjectDiagnostic)
    assert issue.code == PolicyProjectDiagnosticCode.INVALID_PATH.value
    assert issue.path == "linked.dtr"


def test_policy_project_reports_missing_project_files_without_a_traceback(tmp_path: Path) -> None:
    manifest_path = tmp_path / "kiwi.policy.json"
    manifest_path.write_text(_manifest("src/missing.dtr#hold"), encoding="utf-8")

    result = validate_policy_project_file(manifest_path)

    assert isinstance(result, PolicyProjectValidationFailure)
    issue = result.issues[0]
    assert isinstance(issue, PolicyProjectDiagnostic)
    assert issue.code == PolicyProjectDiagnosticCode.MISSING_FILE.value
    assert issue.path == "src/missing.dtr"


def test_policy_project_preserves_compiler_diagnostics_from_declared_sources(
    tmp_path: Path,
) -> None:
    manifest_path = _write_project(
        tmp_path,
        _manifest("src/policy.dtr#hold"),
        "policy hold(value Int) -> Int = value",
    )

    result = validate_policy_project_file(manifest_path)

    assert isinstance(result, PolicyProjectValidationFailure)
    issue = result.issues[0]
    assert isinstance(issue, Diagnostic)
    assert issue.code == "E201_EXPECTED_TOKEN"
    assert issue.primary_span.file_id.value == "src/policy.dtr"


def test_policy_project_requires_declared_policy_entry_points(tmp_path: Path) -> None:
    manifest_path = _write_project(
        tmp_path,
        _manifest("src/policy.dtr#hold"),
        "fn hold() -> Int = 1",
    )

    result = validate_policy_project_file(manifest_path)

    assert isinstance(result, PolicyProjectValidationFailure)
    issue = result.issues[0]
    assert isinstance(issue, PolicyProjectDiagnostic)
    assert issue.code == PolicyProjectDiagnosticCode.ENTRY_NOT_FOUND.value
    assert issue.path == "$.entry_points.operative"


def test_policy_project_rejects_non_object_parameters(tmp_path: Path) -> None:
    (tmp_path / "parameters.json").write_text("[]", encoding="utf-8")
    manifest_path = _write_project(
        tmp_path,
        _manifest("src/policy.dtr#hold", parameters="parameters.json"),
        _VALID_POLICY,
    )

    result = validate_policy_project_file(manifest_path)

    assert isinstance(result, PolicyProjectValidationFailure)
    issue = result.issues[0]
    assert isinstance(issue, PolicyProjectDiagnostic)
    assert issue.code == PolicyProjectDiagnosticCode.INVALID_PARAMETERS.value
    assert issue.path == "parameters.json"
