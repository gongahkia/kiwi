"""Deterministic changed-consequence comparison for two retained causal traces."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EntityId
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.trace.model import CausalTrace, ConsequenceTrace, TraceConsequenceKind


class ConsequenceDifferenceKind(StrEnum):
    """Closed ways one retained consequence can differ between two runs."""

    ADDED = "added"
    REMOVED = "removed"
    CHANGED = "changed"


@dataclass(frozen=True, slots=True)
class ConsequenceComparisonKey:
    """Logical identity of one consequence independent of run-local allocation IDs."""

    tick: int
    kind: TraceConsequenceKind
    subject_entity_ids: tuple[EntityId, ...]

    def __post_init__(self) -> None:
        if (
            not isinstance(self.tick, int)
            or isinstance(self.tick, bool)
            or not 0 <= self.tick <= MAX_AUTHORITY_TICK
        ):
            raise ValueError("consequence comparison key requires an authority tick")
        if not isinstance(self.kind, TraceConsequenceKind):
            raise ValueError("consequence comparison key requires a consequence kind")
        if not isinstance(self.subject_entity_ids, tuple):
            raise ValueError("consequence comparison key requires an immutable subject ID tuple")
        previous_entity_id = 0
        for entity_id in self.subject_entity_ids:
            if not isinstance(entity_id, EntityId) or entity_id.value <= previous_entity_id:
                raise ValueError("consequence comparison key subject IDs must be ascending")
            previous_entity_id = entity_id.value


@dataclass(frozen=True, slots=True)
class ConsequenceDifference:
    """One added, removed, or changed logical consequence with exact trace records."""

    kind: ConsequenceDifferenceKind
    key: ConsequenceComparisonKey
    expected: ConsequenceTrace | None
    actual: ConsequenceTrace | None

    def __post_init__(self) -> None:
        if not isinstance(self.kind, ConsequenceDifferenceKind):
            raise ValueError("consequence difference requires a kind")
        if not isinstance(self.key, ConsequenceComparisonKey):
            raise ValueError("consequence difference requires a key")
        _require_records(self.kind, self.expected, self.actual)
        for consequence in (self.expected, self.actual):
            if consequence is not None and _consequence_key(consequence) != self.key:
                raise ValueError("consequence difference records must match their key")
        if self.kind is ConsequenceDifferenceKind.CHANGED:
            assert self.expected is not None and self.actual is not None
            if _same_consequence(self.expected, self.actual):
                raise ValueError("changed consequence difference requires distinct consequences")


@dataclass(frozen=True, slots=True)
class ConsequenceComparison:
    """All changed consequences in explicit canonical key order."""

    differences: tuple[ConsequenceDifference, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.differences, tuple):
            raise ValueError("consequence comparison differences must be an immutable tuple")
        if any(
            not isinstance(difference, ConsequenceDifference) for difference in self.differences
        ):
            raise ValueError("consequence comparison differences must be structured differences")
        keys = tuple(difference.key for difference in self.differences)
        if keys != tuple(sorted(keys, key=_key_order)) or _has_adjacent_duplicates(keys):
            raise ValueError("consequence comparison differences must use unique canonical keys")

    @property
    def matches(self) -> bool:
        """Return whether both traces retain equivalent logical consequences."""
        return not self.differences


def compare_consequences(expected: CausalTrace, actual: CausalTrace) -> ConsequenceComparison:
    """Return all retained consequence deltas without treating allocation IDs as semantic."""
    if not isinstance(expected, CausalTrace) or not isinstance(actual, CausalTrace):
        raise TypeError("consequence comparison requires CausalTrace values")
    expected_consequences = _consequences(expected)
    actual_consequences = _consequences(actual)
    differences: list[ConsequenceDifference] = []
    expected_index = 0
    actual_index = 0
    while expected_index < len(expected_consequences) or actual_index < len(actual_consequences):
        expected_consequence = _entry(expected_consequences, expected_index)
        actual_consequence = _entry(actual_consequences, actual_index)
        if expected_consequence is None:
            assert actual_consequence is not None
            differences.append(
                ConsequenceDifference(
                    ConsequenceDifferenceKind.ADDED,
                    _consequence_key(actual_consequence),
                    None,
                    actual_consequence,
                )
            )
            actual_index += 1
        elif actual_consequence is None:
            differences.append(
                ConsequenceDifference(
                    ConsequenceDifferenceKind.REMOVED,
                    _consequence_key(expected_consequence),
                    expected_consequence,
                    None,
                )
            )
            expected_index += 1
        else:
            expected_key = _consequence_key(expected_consequence)
            actual_key = _consequence_key(actual_consequence)
            if _key_order(expected_key) < _key_order(actual_key):
                differences.append(
                    ConsequenceDifference(
                        ConsequenceDifferenceKind.REMOVED,
                        expected_key,
                        expected_consequence,
                        None,
                    )
                )
                expected_index += 1
            elif _key_order(expected_key) > _key_order(actual_key):
                differences.append(
                    ConsequenceDifference(
                        ConsequenceDifferenceKind.ADDED,
                        actual_key,
                        None,
                        actual_consequence,
                    )
                )
                actual_index += 1
            else:
                if not _same_consequence(expected_consequence, actual_consequence):
                    differences.append(
                        ConsequenceDifference(
                            ConsequenceDifferenceKind.CHANGED,
                            expected_key,
                            expected_consequence,
                            actual_consequence,
                        )
                    )
                expected_index += 1
                actual_index += 1
    return ConsequenceComparison(tuple(differences))


def _consequences(trace: CausalTrace) -> tuple[ConsequenceTrace, ...]:
    consequences = tuple(record for record in trace.records if isinstance(record, ConsequenceTrace))
    keys = tuple(_consequence_key(consequence) for consequence in consequences)
    if keys != tuple(sorted(keys, key=_key_order)) or _has_adjacent_duplicates(keys):
        raise ValueError("causal trace consequences must have unique canonical keys")
    return consequences


def _consequence_key(consequence: ConsequenceTrace) -> ConsequenceComparisonKey:
    return ConsequenceComparisonKey(
        consequence.tick,
        consequence.kind,
        consequence.subject_entity_ids,
    )


def _key_order(key: ConsequenceComparisonKey) -> tuple[int, str, tuple[int, ...]]:
    return (
        key.tick,
        key.kind.value,
        tuple(entity_id.value for entity_id in key.subject_entity_ids),
    )


def _same_consequence(expected: ConsequenceTrace, actual: ConsequenceTrace) -> bool:
    return expected.summary == actual.summary


def _entry[T](entries: tuple[T, ...], index: int) -> T | None:
    if index == len(entries):
        return None
    return entries[index]


def _has_adjacent_duplicates[T](values: tuple[T, ...]) -> bool:
    return any(first == second for first, second in zip(values, values[1:], strict=False))


def _require_records(
    kind: ConsequenceDifferenceKind,
    expected: ConsequenceTrace | None,
    actual: ConsequenceTrace | None,
) -> None:
    if expected is not None and not isinstance(expected, ConsequenceTrace):
        raise ValueError("consequence difference expected record is invalid")
    if actual is not None and not isinstance(actual, ConsequenceTrace):
        raise ValueError("consequence difference actual record is invalid")
    if kind is ConsequenceDifferenceKind.ADDED and (expected is not None or actual is None):
        raise ValueError("added consequence difference requires only an actual record")
    if kind is ConsequenceDifferenceKind.REMOVED and (expected is None or actual is not None):
        raise ValueError("removed consequence difference requires only an expected record")
    if kind is ConsequenceDifferenceKind.CHANGED and (expected is None or actual is None):
        raise ValueError("changed consequence difference requires both records")
