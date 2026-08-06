"""Deterministic development-only policy and kernel-fixture picker state."""

from __future__ import annotations

from dataclasses import dataclass, replace
from pathlib import Path

from kiwi.content.fixtures import FixtureLoadResult, load_kernel_fixture_file
from kiwi.dsl.source import SourceFileId, SourceLoadResult, load_utf8_file


@dataclass(frozen=True, slots=True)
class PickerOption:
    """One discovered development file with a stable root-relative label."""

    path: Path
    label: str

    def __post_init__(self) -> None:
        if not isinstance(self.path, Path):
            raise TypeError("picker option path must be a path")
        if not isinstance(self.label, str) or not self.label:
            raise ValueError("picker option label must be non-empty")


@dataclass(frozen=True, slots=True)
class DevelopmentPicker:
    """Immutable development picker selections over canonically ordered file options."""

    policies: tuple[PickerOption, ...]
    fixtures: tuple[PickerOption, ...]
    selected_policy: Path | None
    selected_fixture: Path | None

    def __post_init__(self) -> None:
        _validate_options(self.policies, "policy")
        _validate_options(self.fixtures, "fixture")
        _validate_selection(self.selected_policy, self.policies, "policy")
        _validate_selection(self.selected_fixture, self.fixtures, "fixture")

    def select_policy(self, path: Path) -> DevelopmentPicker:
        """Return the picker selecting one discovered policy file."""
        _validate_selection(path, self.policies, "policy")
        return replace(self, selected_policy=path)

    def select_fixture(self, path: Path) -> DevelopmentPicker:
        """Return the picker selecting one discovered fixture file."""
        _validate_selection(path, self.fixtures, "fixture")
        return replace(self, selected_fixture=path)

    def load_selected_policy(self) -> SourceLoadResult:
        """Load the selected policy at the UI filesystem boundary."""
        if self.selected_policy is None:
            raise ValueError("no policy is selected")
        return load_utf8_file(self.selected_policy, file_id=SourceFileId(str(self.selected_policy)))

    def load_selected_fixture(self) -> FixtureLoadResult:
        """Load and validate the selected kernel fixture at the UI filesystem boundary."""
        if self.selected_fixture is None:
            raise ValueError("no fixture is selected")
        return load_kernel_fixture_file(self.selected_fixture)


def discover_development_picker(
    policy_roots: tuple[Path, ...],
    fixture_roots: tuple[Path, ...],
) -> DevelopmentPicker:
    """Discover policy and fixture files in root and relative-path canonical order."""
    policies = _discover(policy_roots, "*.dtr")
    fixtures = _discover(fixture_roots, "*.kfixture.json")
    return DevelopmentPicker(
        policies,
        fixtures,
        policies[0].path if policies else None,
        fixtures[0].path if fixtures else None,
    )


def _discover(roots: tuple[Path, ...], pattern: str) -> tuple[PickerOption, ...]:
    if not isinstance(roots, tuple) or any(not isinstance(root, Path) for root in roots):
        raise TypeError("development picker roots must be a tuple of paths")
    options: list[PickerOption] = []
    for root in sorted(roots, key=lambda item: item.as_posix()):
        if not root.is_dir():
            raise ValueError(f"development picker root is not a directory: {root}")
        for path in sorted(root.rglob(pattern), key=lambda item: item.relative_to(root).as_posix()):
            if path.is_file():
                options.append(
                    PickerOption(path, f"{root.name}/{path.relative_to(root).as_posix()}")
                )
    return tuple(sorted(options, key=lambda item: (item.label, item.path.as_posix())))


def _validate_options(options: tuple[PickerOption, ...], kind: str) -> None:
    if not isinstance(options, tuple) or any(
        not isinstance(option, PickerOption) for option in options
    ):
        raise TypeError(f"picker {kind} options must be a tuple of picker options")
    keys = tuple((option.label, option.path.as_posix()) for option in options)
    if keys != tuple(sorted(keys)) or len({option.path for option in options}) != len(options):
        raise ValueError(f"picker {kind} options must be unique and canonically ordered")


def _validate_selection(path: Path | None, options: tuple[PickerOption, ...], kind: str) -> None:
    if path is not None and not isinstance(path, Path):
        raise TypeError(f"picker {kind} selection must be a path or None")
    if path is not None and path not in tuple(option.path for option in options):
        raise ValueError(f"picker {kind} selection is not discovered")
