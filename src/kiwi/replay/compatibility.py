"""Deterministic common-baseline checks before comparing replay outcomes."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EntityId
from kiwi.replay.format import ReplayPacket
from kiwi.sim.policy_versions import EntityPolicyVersion, PolicyVersion


class RunCompatibilityFailureCode(StrEnum):
    """Stable reasons two recorded runs cannot be compared as one experiment."""

    APPLICATION_BUILD = "RC001_APPLICATION_BUILD"
    SIMULATION_VERSION = "RC002_SIMULATION_VERSION"
    MISSION = "RC003_MISSION"
    INITIAL_SNAPSHOT = "RC004_INITIAL_SNAPSHOT"
    SEED = "RC005_SEED"
    TICK_RATE = "RC006_TICK_RATE"
    COMMAND_LOG = "RC007_COMMAND_LOG"


class PolicyVersionDifferenceKind(StrEnum):
    """One canonical deployed-policy change between otherwise comparable runs."""

    ADDED = "added"
    REMOVED = "removed"
    CHANGED = "changed"


@dataclass(frozen=True, slots=True)
class RunCompatibilityFailure:
    """One baseline mismatch with a stable code and player-safe message."""

    code: RunCompatibilityFailureCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, RunCompatibilityFailureCode):
            raise ValueError("run compatibility failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("run compatibility failure requires a message")


@dataclass(frozen=True, slots=True)
class PolicyVersionDifference:
    """One entity-ID-ordered policy manifest delta retained for comparison output."""

    entity_id: EntityId
    kind: PolicyVersionDifferenceKind
    expected_version: PolicyVersion | None
    actual_version: PolicyVersion | None

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("policy version difference requires an entity ID")
        if not isinstance(self.kind, PolicyVersionDifferenceKind):
            raise ValueError("policy version difference requires a kind")
        if self.expected_version is not None and not isinstance(
            self.expected_version, PolicyVersion
        ):
            raise ValueError("policy version difference expected version is invalid")
        if self.actual_version is not None and not isinstance(self.actual_version, PolicyVersion):
            raise ValueError("policy version difference actual version is invalid")
        match self.kind:
            case PolicyVersionDifferenceKind.ADDED:
                if self.expected_version is not None or self.actual_version is None:
                    raise ValueError(
                        "added policy version difference requires only an actual version"
                    )
            case PolicyVersionDifferenceKind.REMOVED:
                if self.expected_version is None or self.actual_version is not None:
                    raise ValueError(
                        "removed policy version difference requires only an expected version"
                    )
            case PolicyVersionDifferenceKind.CHANGED:
                if (
                    self.expected_version is None
                    or self.actual_version is None
                    or self.expected_version == self.actual_version
                ):
                    raise ValueError("changed policy version difference requires distinct versions")


@dataclass(frozen=True, slots=True)
class RunCompatibility:
    """Compatibility failures and explicit policy deltas for a pair of replay packets."""

    failures: tuple[RunCompatibilityFailure, ...]
    policy_differences: tuple[PolicyVersionDifference, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.failures, tuple):
            raise ValueError("run compatibility failures must be an immutable tuple")
        if any(not isinstance(failure, RunCompatibilityFailure) for failure in self.failures):
            raise ValueError("run compatibility failures must be structured failures")
        failure_codes = tuple(failure.code for failure in self.failures)
        if failure_codes != tuple(sorted(failure_codes)) or _has_adjacent_duplicates(failure_codes):
            raise ValueError("run compatibility failures must be unique and code ordered")
        if not isinstance(self.policy_differences, tuple):
            raise ValueError("run compatibility policy differences must be an immutable tuple")
        if any(
            not isinstance(difference, PolicyVersionDifference)
            for difference in self.policy_differences
        ):
            raise ValueError("run compatibility policy differences must be structured differences")
        entity_ids = tuple(difference.entity_id for difference in self.policy_differences)
        if entity_ids != tuple(sorted(entity_ids, key=lambda entity_id: entity_id.value)) or (
            _has_adjacent_duplicates(entity_ids)
        ):
            raise ValueError("run compatibility policy differences must be entity-ID ordered")

    @property
    def is_compatible(self) -> bool:
        """Return whether the two replays share a valid controlled-experiment baseline."""
        return not self.failures


def check_run_compatibility(expected: ReplayPacket, actual: ReplayPacket) -> RunCompatibility:
    """Compare two replay inputs while allowing explicit deployed-policy changes."""
    if not isinstance(expected, ReplayPacket) or not isinstance(actual, ReplayPacket):
        raise TypeError("run compatibility requires ReplayPacket values")
    failures: list[RunCompatibilityFailure] = []
    if expected.application_build != actual.application_build:
        failures.append(
            RunCompatibilityFailure(
                RunCompatibilityFailureCode.APPLICATION_BUILD,
                "application builds differ",
            )
        )
    if expected.simulation_version != actual.simulation_version:
        failures.append(
            RunCompatibilityFailure(
                RunCompatibilityFailureCode.SIMULATION_VERSION,
                "simulation versions differ",
            )
        )
    if expected.mission_hash != actual.mission_hash:
        failures.append(
            RunCompatibilityFailure(
                RunCompatibilityFailureCode.MISSION,
                "mission content hashes differ",
            )
        )
    if expected.initial_snapshot != actual.initial_snapshot:
        failures.append(
            RunCompatibilityFailure(
                RunCompatibilityFailureCode.INITIAL_SNAPSHOT,
                "initial authority snapshots differ",
            )
        )
    if expected.seed != actual.seed:
        failures.append(
            RunCompatibilityFailure(
                RunCompatibilityFailureCode.SEED,
                "mission seeds differ",
            )
        )
    if expected.tick_rate != actual.tick_rate:
        failures.append(
            RunCompatibilityFailure(
                RunCompatibilityFailureCode.TICK_RATE,
                "fixed tick rates differ",
            )
        )
    if expected.commands != actual.commands:
        failures.append(
            RunCompatibilityFailure(
                RunCompatibilityFailureCode.COMMAND_LOG,
                "canonical command logs differ",
            )
        )
    return RunCompatibility(tuple(failures), _policy_differences(expected, actual))


def _policy_differences(
    expected: ReplayPacket,
    actual: ReplayPacket,
) -> tuple[PolicyVersionDifference, ...]:
    differences: list[PolicyVersionDifference] = []
    expected_index = 0
    actual_index = 0
    while expected_index < len(expected.policy_versions) or actual_index < len(
        actual.policy_versions
    ):
        expected_entry = _policy_entry(expected.policy_versions, expected_index)
        actual_entry = _policy_entry(actual.policy_versions, actual_index)
        if expected_entry is None:
            assert actual_entry is not None
            differences.append(
                PolicyVersionDifference(
                    actual_entry.entity_id,
                    PolicyVersionDifferenceKind.ADDED,
                    None,
                    actual_entry.version,
                )
            )
            actual_index += 1
        elif actual_entry is None:
            differences.append(
                PolicyVersionDifference(
                    expected_entry.entity_id,
                    PolicyVersionDifferenceKind.REMOVED,
                    expected_entry.version,
                    None,
                )
            )
            expected_index += 1
        elif expected_entry.entity_id.value < actual_entry.entity_id.value:
            differences.append(
                PolicyVersionDifference(
                    expected_entry.entity_id,
                    PolicyVersionDifferenceKind.REMOVED,
                    expected_entry.version,
                    None,
                )
            )
            expected_index += 1
        elif expected_entry.entity_id.value > actual_entry.entity_id.value:
            differences.append(
                PolicyVersionDifference(
                    actual_entry.entity_id,
                    PolicyVersionDifferenceKind.ADDED,
                    None,
                    actual_entry.version,
                )
            )
            actual_index += 1
        elif expected_entry.version != actual_entry.version:
            differences.append(
                PolicyVersionDifference(
                    expected_entry.entity_id,
                    PolicyVersionDifferenceKind.CHANGED,
                    expected_entry.version,
                    actual_entry.version,
                )
            )
            expected_index += 1
            actual_index += 1
        else:
            expected_index += 1
            actual_index += 1
    return tuple(differences)


def _policy_entry(
    entries: tuple[EntityPolicyVersion, ...],
    index: int,
) -> EntityPolicyVersion | None:
    if index == len(entries):
        return None
    return entries[index]


def _has_adjacent_duplicates[T](values: tuple[T, ...]) -> bool:
    return any(first == second for first, second in zip(values, values[1:], strict=False))
