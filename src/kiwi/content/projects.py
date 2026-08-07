"""Strict policy-project manifest loading and closed-DSL validation."""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path, PurePosixPath
from typing import cast

from kiwi.dsl.bytecode import SOURCE_LANGUAGE_VERSION, BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.diagnostics import Diagnostic
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId, SourceLoadFailure, load_utf8_file

POLICY_PROJECT_FILENAME = "kiwi.policy.json"
POLICY_PROJECT_FORMAT = "kiwi-policy-project"
POLICY_PROJECT_VERSION = 1
MAX_POLICY_PROJECT_BYTES = 1_048_576


class PolicyProjectDiagnosticCode(StrEnum):
    """Stable policy-project validation failures outside the DSL."""

    READ_FAILED = "P001_READ_FAILED"
    TOO_LARGE = "P002_TOO_LARGE"
    INVALID_UTF8 = "P003_INVALID_UTF8"
    INVALID_JSON = "P004_INVALID_JSON"
    DUPLICATE_FIELD = "P005_DUPLICATE_FIELD"
    INVALID_STRUCTURE = "P006_INVALID_STRUCTURE"
    UNSUPPORTED_VERSION = "P007_UNSUPPORTED_VERSION"
    INVALID_PATH = "P008_INVALID_PATH"
    MISSING_FILE = "P009_MISSING_FILE"
    INVALID_PARAMETERS = "P010_INVALID_PARAMETERS"
    ENTRY_NOT_FOUND = "P011_ENTRY_NOT_FOUND"


@dataclass(frozen=True, slots=True)
class PolicyProjectDiagnostic:
    """One manifest, path, or source-load validation issue."""

    code: str
    path: str
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, str) or not self.code:
            raise ValueError("policy project diagnostic code must be text")
        if not isinstance(self.path, str) or not self.path:
            raise ValueError("policy project diagnostic path must be text")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("policy project diagnostic message must be text")


type PolicyProjectIssue = PolicyProjectDiagnostic | Diagnostic


@dataclass(frozen=True, slots=True)
class PolicyProjectEntry:
    """One named policy entry resolved from a root-confined source reference."""

    name: str
    source_path: PurePosixPath
    function_name: str

    def __post_init__(self) -> None:
        if not _is_identifier(self.name):
            raise ValueError("policy project entry name must be a lowercase ASCII identifier")
        if not isinstance(self.source_path, PurePosixPath) or not _is_safe_relative_path(
            self.source_path
        ):
            raise ValueError("policy project source path must be a safe relative path")
        if self.source_path.suffix != ".dtr":
            raise ValueError("policy project source path must reference a .dtr file")
        if not _is_identifier(self.function_name):
            raise ValueError("policy project function name must be a lowercase ASCII identifier")


@dataclass(frozen=True, slots=True)
class PolicyProject:
    """One schema-valid, source-validated policy project."""

    root: Path
    name: str
    language_version: int
    entries: tuple[PolicyProjectEntry, ...]
    parameters_path: PurePosixPath | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.root, Path):
            raise TypeError("policy project root must be a path")
        if not _is_project_name(self.name):
            raise ValueError("policy project name must be lowercase ASCII text")
        if self.language_version != SOURCE_LANGUAGE_VERSION:
            raise ValueError("policy project language version is unsupported")
        if not isinstance(self.entries, tuple) or not self.entries:
            raise ValueError("policy project requires immutable entry points")
        if any(not isinstance(entry, PolicyProjectEntry) for entry in self.entries):
            raise TypeError("policy project entries are invalid")
        names = tuple(entry.name for entry in self.entries)
        if names != tuple(sorted(names)) or len(set(names)) != len(names):
            raise ValueError("policy project entries must be lexically ordered and unique")
        if self.parameters_path is not None and (
            not isinstance(self.parameters_path, PurePosixPath)
            or not _is_safe_relative_path(self.parameters_path)
            or self.parameters_path.suffix != ".json"
        ):
            raise ValueError("policy project parameters path must reference a safe .json file")


@dataclass(frozen=True, slots=True)
class PolicyProjectValidationFailure:
    """A deterministic non-throwing validation result for untrusted project files."""

    manifest_path: Path
    issues: tuple[PolicyProjectIssue, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.manifest_path, Path):
            raise TypeError("policy project failure manifest path must be a path")
        if not isinstance(self.issues, tuple) or not self.issues:
            raise ValueError("policy project failure requires immutable issues")
        if any(
            not isinstance(issue, (PolicyProjectDiagnostic, Diagnostic)) for issue in self.issues
        ):
            raise TypeError("policy project failure issues are invalid")


type PolicyProjectValidationResult = PolicyProject | PolicyProjectValidationFailure


def validate_policy_project_file(path: Path) -> PolicyProjectValidationResult:
    """Validate a policy project, its confined sources, and declared policy entries."""
    if not isinstance(path, Path):
        raise TypeError("policy project manifest path must be a path")
    document = _load_manifest(path)
    if isinstance(document, PolicyProjectValidationFailure):
        return document
    parsed = _parse_project(path, document)
    if isinstance(parsed, PolicyProjectValidationFailure):
        return parsed
    project = parsed
    parameter_issue = _validate_parameters(project)
    if parameter_issue is not None:
        return _failure(path, parameter_issue)
    sources, issues = _compile_project_sources(project)
    if issues:
        return PolicyProjectValidationFailure(path, tuple(issues))
    entry_issues = _validate_entries(project, sources)
    if entry_issues:
        return PolicyProjectValidationFailure(path, tuple(entry_issues))
    return project


def _load_manifest(path: Path) -> object | PolicyProjectValidationFailure:
    try:
        with path.open("rb") as manifest_file:
            data = manifest_file.read(MAX_POLICY_PROJECT_BYTES + 1)
    except OSError:
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.READ_FAILED.value,
                "$",
                "could not read policy project manifest",
            ),
        )
    if len(data) > MAX_POLICY_PROJECT_BYTES:
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.TOO_LARGE.value,
                "$",
                "policy project manifest exceeds the byte limit",
            ),
        )
    try:
        return cast(object, json.loads(data.decode("utf-8"), object_pairs_hook=_unique_object))
    except UnicodeDecodeError:
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.INVALID_UTF8.value,
                "$",
                "policy project manifest is not valid UTF-8",
            ),
        )
    except json.JSONDecodeError:
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.INVALID_JSON.value,
                "$",
                "policy project manifest is not valid JSON",
            ),
        )
    except _DuplicateFieldError:
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.DUPLICATE_FIELD.value,
                "$",
                "policy project manifest has duplicate fields",
            ),
        )


def _parse_project(path: Path, document: object) -> PolicyProjectValidationResult:
    if not isinstance(document, dict):
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.INVALID_STRUCTURE.value,
                "$",
                "policy project manifest must be an object",
            ),
        )
    required = {"entry_points", "format", "language_version", "name", "version"}
    optional = {"parameters"}
    if set(document) - required - optional or required - set(document):
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.INVALID_STRUCTURE.value,
                "$",
                "policy project manifest fields are invalid",
            ),
        )
    if document["format"] != POLICY_PROJECT_FORMAT:
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.INVALID_STRUCTURE.value,
                "$.format",
                "policy project format is invalid",
            ),
        )
    if document["version"] != POLICY_PROJECT_VERSION:
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.UNSUPPORTED_VERSION.value,
                "$.version",
                f"unsupported policy project version {document['version']!r}",
            ),
        )
    name = document["name"]
    if not _is_project_name(name):
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.INVALID_STRUCTURE.value,
                "$.name",
                "policy project name must be lowercase ASCII text",
            ),
        )
    language_version = document["language_version"]
    if (
        not isinstance(language_version, int)
        or isinstance(language_version, bool)
        or language_version != SOURCE_LANGUAGE_VERSION
    ):
        return _failure(
            path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.UNSUPPORTED_VERSION.value,
                "$.language_version",
                f"unsupported policy source language version {language_version!r}",
            ),
        )
    entries = _parse_entries(path, document["entry_points"])
    if isinstance(entries, PolicyProjectValidationFailure):
        return entries
    parameters = _parse_parameters_path(path, document.get("parameters"))
    if isinstance(parameters, PolicyProjectValidationFailure):
        return parameters
    return PolicyProject(path.parent.resolve(), name, language_version, entries, parameters)


def _parse_entries(
    manifest_path: Path,
    value: object,
) -> tuple[PolicyProjectEntry, ...] | PolicyProjectValidationFailure:
    if not isinstance(value, dict) or not value:
        return _failure(
            manifest_path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.INVALID_STRUCTURE.value,
                "$.entry_points",
                "policy project entry points must be a non-empty object",
            ),
        )
    entries: list[PolicyProjectEntry] = []
    for entry_name, reference in sorted(value.items()):
        location = f"$.entry_points.{entry_name}"
        if not _is_identifier(entry_name) or not isinstance(reference, str):
            return _failure(
                manifest_path,
                PolicyProjectDiagnostic(
                    PolicyProjectDiagnosticCode.INVALID_STRUCTURE.value,
                    location,
                    "policy project entry point must map a lowercase name to text",
                ),
            )
        source_path, function_name = _parse_entry_reference(reference)
        if source_path is None or not _is_identifier(function_name):
            return _failure(
                manifest_path,
                PolicyProjectDiagnostic(
                    PolicyProjectDiagnosticCode.INVALID_PATH.value,
                    location,
                    "policy project entry must use relative/path.dtr#policy_name",
                ),
            )
        try:
            entries.append(PolicyProjectEntry(entry_name, source_path, function_name))
        except ValueError as error:
            return _failure(
                manifest_path,
                PolicyProjectDiagnostic(
                    PolicyProjectDiagnosticCode.INVALID_PATH.value,
                    location,
                    str(error),
                ),
            )
    return tuple(entries)


def _parse_parameters_path(
    manifest_path: Path,
    value: object,
) -> PurePosixPath | None | PolicyProjectValidationFailure:
    if value is None:
        return None
    if not isinstance(value, str):
        return _failure(
            manifest_path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.INVALID_PATH.value,
                "$.parameters",
                "policy project parameters must reference a relative .json file",
            ),
        )
    path = _safe_relative_path(value)
    if path is None or path.suffix != ".json":
        return _failure(
            manifest_path,
            PolicyProjectDiagnostic(
                PolicyProjectDiagnosticCode.INVALID_PATH.value,
                "$.parameters",
                "policy project parameters must reference a relative .json file",
            ),
        )
    return path


def _compile_project_sources(
    project: PolicyProject,
) -> tuple[dict[PurePosixPath, CompiledArtifact], list[PolicyProjectIssue]]:
    artifacts: dict[PurePosixPath, CompiledArtifact] = {}
    issues: list[PolicyProjectIssue] = []
    for source_path in tuple(sorted({entry.source_path for entry in project.entries})):
        resolved, issue = _resolve_project_file(project, source_path)
        if issue is not None:
            issues.append(issue)
            continue
        loaded = load_utf8_file(resolved, file_id=SourceFileId(source_path.as_posix()))
        if isinstance(loaded, SourceLoadFailure):
            issues.append(
                PolicyProjectDiagnostic(
                    loaded.code.value,
                    source_path.as_posix(),
                    loaded.message,
                )
            )
            continue
        artifact, source_issues = _compile_source(loaded)
        if source_issues:
            issues.extend(source_issues)
            continue
        if artifact is None:
            raise AssertionError("diagnostic-free policy source has no compiled artifact")
        artifacts[source_path] = artifact
    return artifacts, issues


def _compile_source(
    source: SourceFile,
) -> tuple[CompiledArtifact | None, tuple[Diagnostic, ...]]:
    parsed = parse(lex(source))
    if parsed.diagnostics:
        return None, parsed.diagnostics
    checked = check(resolve(parsed.module))
    if checked.diagnostics:
        return None, checked.diagnostics
    if checked.module is None:
        raise AssertionError("diagnostic-free policy project source has no typed module")
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id)), ()


def _validate_entries(
    project: PolicyProject,
    artifacts: dict[PurePosixPath, CompiledArtifact],
) -> list[PolicyProjectDiagnostic]:
    issues: list[PolicyProjectDiagnostic] = []
    for entry in project.entries:
        artifact = artifacts[entry.source_path]
        available = tuple(capability.name for capability in artifact.capability_manifest.entries)
        if entry.function_name not in available:
            issues.append(
                PolicyProjectDiagnostic(
                    PolicyProjectDiagnosticCode.ENTRY_NOT_FOUND.value,
                    f"$.entry_points.{entry.name}",
                    f"policy {entry.function_name!r} is not declared by "
                    f"{entry.source_path.as_posix()}",
                )
            )
    return issues


def _validate_parameters(project: PolicyProject) -> PolicyProjectDiagnostic | None:
    if project.parameters_path is None:
        return None
    resolved, issue = _resolve_project_file(project, project.parameters_path)
    if issue is not None:
        return issue
    try:
        with resolved.open("rb") as parameters_file:
            data = parameters_file.read(MAX_POLICY_PROJECT_BYTES + 1)
    except OSError:
        return PolicyProjectDiagnostic(
            PolicyProjectDiagnosticCode.READ_FAILED.value,
            project.parameters_path.as_posix(),
            "could not read policy project parameters",
        )
    if len(data) > MAX_POLICY_PROJECT_BYTES:
        return PolicyProjectDiagnostic(
            PolicyProjectDiagnosticCode.TOO_LARGE.value,
            project.parameters_path.as_posix(),
            "policy project parameters exceed the byte limit",
        )
    try:
        document = json.loads(data.decode("utf-8"), object_pairs_hook=_unique_object)
    except UnicodeDecodeError:
        return PolicyProjectDiagnostic(
            PolicyProjectDiagnosticCode.INVALID_UTF8.value,
            project.parameters_path.as_posix(),
            "policy project parameters are not valid UTF-8",
        )
    except json.JSONDecodeError:
        return PolicyProjectDiagnostic(
            PolicyProjectDiagnosticCode.INVALID_JSON.value,
            project.parameters_path.as_posix(),
            "policy project parameters are not valid JSON",
        )
    except _DuplicateFieldError:
        return PolicyProjectDiagnostic(
            PolicyProjectDiagnosticCode.DUPLICATE_FIELD.value,
            project.parameters_path.as_posix(),
            "policy project parameters have duplicate fields",
        )
    if not isinstance(document, dict):
        return PolicyProjectDiagnostic(
            PolicyProjectDiagnosticCode.INVALID_PARAMETERS.value,
            project.parameters_path.as_posix(),
            "policy project parameters must be an object",
        )
    return None


def _resolve_project_file(
    project: PolicyProject,
    relative_path: PurePosixPath,
) -> tuple[Path, PolicyProjectDiagnostic | None]:
    candidate = project.root.joinpath(*relative_path.parts)
    try:
        resolved = candidate.resolve(strict=False)
    except OSError:
        return candidate, PolicyProjectDiagnostic(
            PolicyProjectDiagnosticCode.READ_FAILED.value,
            relative_path.as_posix(),
            "could not resolve policy project file",
        )
    if not resolved.is_relative_to(project.root):
        return resolved, PolicyProjectDiagnostic(
            PolicyProjectDiagnosticCode.INVALID_PATH.value,
            relative_path.as_posix(),
            "policy project file escapes its root",
        )
    if not resolved.is_file():
        return resolved, PolicyProjectDiagnostic(
            PolicyProjectDiagnosticCode.MISSING_FILE.value,
            relative_path.as_posix(),
            "policy project file does not exist",
        )
    return resolved, None


def _parse_entry_reference(value: str) -> tuple[PurePosixPath | None, str]:
    if value.count("#") != 1:
        return None, ""
    source_text, function_name = value.split("#", maxsplit=1)
    return _safe_relative_path(source_text), function_name


def _safe_relative_path(value: str) -> PurePosixPath | None:
    if not isinstance(value, str) or not value or "\\" in value:
        return None
    path = PurePosixPath(value)
    return path if _is_safe_relative_path(path) else None


def _is_safe_relative_path(path: PurePosixPath) -> bool:
    return (
        not path.is_absolute()
        and bool(path.parts)
        and all(part not in ("", ".", "..") for part in path.parts)
    )


def _is_identifier(value: object) -> bool:
    return (
        isinstance(value, str)
        and value.isascii()
        and value.isidentifier()
        and value == value.lower()
    )


def _is_project_name(value: object) -> bool:
    return (
        isinstance(value, str)
        and value.isascii()
        and bool(value)
        and all(
            character.islower() or character.isdigit() or character == "-" for character in value
        )
        and value[0].islower()
        and value[-1] != "-"
    )


def _failure(path: Path, issue: PolicyProjectIssue) -> PolicyProjectValidationFailure:
    return PolicyProjectValidationFailure(path, (issue,))


class _DuplicateFieldError(ValueError):
    pass


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise _DuplicateFieldError
        result[key] = value
    return result
