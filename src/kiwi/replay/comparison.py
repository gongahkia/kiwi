"""First policy-evaluation and intention differences between two headless runs."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EntityId
from kiwi.sim.events import IntentionEmitted, PolicyEvaluated
from kiwi.sim.intentions import IntentionOrigin
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.runner import HeadlessRun


class RunDifferenceKind(StrEnum):
    """Closed ways one comparison stream can differ at a shared logical key."""

    ADDED = "added"
    REMOVED = "removed"
    CHANGED = "changed"


@dataclass(frozen=True, slots=True)
class PolicyEvaluationComparisonKey:
    """The canonical logical identity of one policy evaluation in a run."""

    tick: int
    entity_id: EntityId

    def __post_init__(self) -> None:
        if (
            not isinstance(self.tick, int)
            or isinstance(self.tick, bool)
            or not 0 <= self.tick <= MAX_AUTHORITY_TICK
        ):
            raise ValueError("policy evaluation comparison key requires an authority tick")
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("policy evaluation comparison key requires an entity ID")


@dataclass(frozen=True, slots=True)
class IntentionComparisonKey:
    """The canonical logical identity of one emitted policy intention."""

    tick: int
    issuer_entity_id: EntityId
    policy_order: int

    def __post_init__(self) -> None:
        if (
            not isinstance(self.tick, int)
            or isinstance(self.tick, bool)
            or not 0 <= self.tick <= MAX_AUTHORITY_TICK
        ):
            raise ValueError("intention comparison key requires an authority tick")
        if not isinstance(self.issuer_entity_id, EntityId):
            raise ValueError("intention comparison key requires an entity ID")
        if (
            not isinstance(self.policy_order, int)
            or isinstance(self.policy_order, bool)
            or self.policy_order < 0
        ):
            raise ValueError("intention comparison key requires a non-negative policy order")


@dataclass(frozen=True, slots=True)
class PolicyEvaluationDifference:
    """The earliest differing retained policy evaluation, if present in each run."""

    kind: RunDifferenceKind
    key: PolicyEvaluationComparisonKey
    expected: PolicyEvaluated | None
    actual: PolicyEvaluated | None

    def __post_init__(self) -> None:
        if not isinstance(self.kind, RunDifferenceKind):
            raise ValueError("policy evaluation difference requires a kind")
        if not isinstance(self.key, PolicyEvaluationComparisonKey):
            raise ValueError("policy evaluation difference requires a key")
        _require_difference_records(
            self.kind,
            self.expected,
            self.actual,
            PolicyEvaluated,
            "policy evaluation",
        )
        for event in (self.expected, self.actual):
            if event is None:
                continue
            if _policy_evaluation_key(event) != self.key:
                raise ValueError("policy evaluation difference records must match their key")
        if self.kind is RunDifferenceKind.CHANGED:
            assert self.expected is not None and self.actual is not None
            if self.expected.validation == self.actual.validation:
                raise ValueError(
                    "changed policy evaluation difference requires distinct evaluations"
                )


@dataclass(frozen=True, slots=True)
class IntentionDifference:
    """The earliest differing emitted intention, if present in each run."""

    kind: RunDifferenceKind
    key: IntentionComparisonKey
    expected: IntentionEmitted | None
    actual: IntentionEmitted | None

    def __post_init__(self) -> None:
        if not isinstance(self.kind, RunDifferenceKind):
            raise ValueError("intention difference requires a kind")
        if not isinstance(self.key, IntentionComparisonKey):
            raise ValueError("intention difference requires a key")
        _require_difference_records(
            self.kind,
            self.expected,
            self.actual,
            IntentionEmitted,
            "intention",
        )
        for event in (self.expected, self.actual):
            if event is None:
                continue
            if _intention_key(event) != self.key:
                raise ValueError("intention difference records must match their key")
        if self.kind is RunDifferenceKind.CHANGED:
            assert self.expected is not None and self.actual is not None
            if _same_emitted_intention(self.expected, self.actual):
                raise ValueError("changed intention difference requires distinct intentions")


@dataclass(frozen=True, slots=True)
class PolicyExecutionComparison:
    """The first known policy-evaluation and emitted-intention differences."""

    evaluation_difference: PolicyEvaluationDifference | None
    intention_difference: IntentionDifference | None

    def __post_init__(self) -> None:
        if self.evaluation_difference is not None and not isinstance(
            self.evaluation_difference, PolicyEvaluationDifference
        ):
            raise ValueError("policy execution comparison evaluation difference is invalid")
        if self.intention_difference is not None and not isinstance(
            self.intention_difference, IntentionDifference
        ):
            raise ValueError("policy execution comparison intention difference is invalid")

    @property
    def matches(self) -> bool:
        """Return whether retained policy evaluations and intentions match."""
        return self.evaluation_difference is None and self.intention_difference is None


def compare_policy_execution(
    expected: HeadlessRun,
    actual: HeadlessRun,
) -> PolicyExecutionComparison:
    """Find first logical policy and intention differences without using allocation IDs."""
    if not isinstance(expected, HeadlessRun) or not isinstance(actual, HeadlessRun):
        raise TypeError("policy execution comparison requires HeadlessRun values")
    expected_evaluations = _policy_evaluations(expected)
    actual_evaluations = _policy_evaluations(actual)
    expected_intentions = _emitted_intentions(expected)
    actual_intentions = _emitted_intentions(actual)
    return PolicyExecutionComparison(
        _first_evaluation_difference(expected_evaluations, actual_evaluations),
        _first_intention_difference(expected_intentions, actual_intentions),
    )


def _policy_evaluations(run: HeadlessRun) -> tuple[PolicyEvaluated, ...]:
    evaluations = tuple(event for event in run.events if isinstance(event, PolicyEvaluated))
    keys = tuple(_policy_evaluation_key(event) for event in evaluations)
    if keys != tuple(sorted(keys, key=_evaluation_key_order)) or _has_adjacent_duplicates(keys):
        raise ValueError("headless run policy evaluations must have unique canonical keys")
    return evaluations


def _emitted_intentions(run: HeadlessRun) -> tuple[IntentionEmitted, ...]:
    intentions = tuple(event for event in run.events if isinstance(event, IntentionEmitted))
    keys = tuple(_intention_key(event) for event in intentions)
    if keys != tuple(sorted(keys, key=_intention_key_order)) or _has_adjacent_duplicates(keys):
        raise ValueError("headless run emitted intentions must have unique canonical keys")
    return intentions


def _first_evaluation_difference(
    expected: tuple[PolicyEvaluated, ...],
    actual: tuple[PolicyEvaluated, ...],
) -> PolicyEvaluationDifference | None:
    expected_index = 0
    actual_index = 0
    while expected_index < len(expected) or actual_index < len(actual):
        expected_event = _entry(expected, expected_index)
        actual_event = _entry(actual, actual_index)
        if expected_event is None:
            assert actual_event is not None
            return PolicyEvaluationDifference(
                RunDifferenceKind.ADDED,
                _policy_evaluation_key(actual_event),
                None,
                actual_event,
            )
        if actual_event is None:
            return PolicyEvaluationDifference(
                RunDifferenceKind.REMOVED,
                _policy_evaluation_key(expected_event),
                expected_event,
                None,
            )
        expected_key = _policy_evaluation_key(expected_event)
        actual_key = _policy_evaluation_key(actual_event)
        if _evaluation_key_order(expected_key) < _evaluation_key_order(actual_key):
            return PolicyEvaluationDifference(
                RunDifferenceKind.REMOVED, expected_key, expected_event, None
            )
        if _evaluation_key_order(expected_key) > _evaluation_key_order(actual_key):
            return PolicyEvaluationDifference(
                RunDifferenceKind.ADDED, actual_key, None, actual_event
            )
        if expected_event.validation != actual_event.validation:
            return PolicyEvaluationDifference(
                RunDifferenceKind.CHANGED,
                expected_key,
                expected_event,
                actual_event,
            )
        expected_index += 1
        actual_index += 1
    return None


def _first_intention_difference(
    expected: tuple[IntentionEmitted, ...],
    actual: tuple[IntentionEmitted, ...],
) -> IntentionDifference | None:
    expected_index = 0
    actual_index = 0
    while expected_index < len(expected) or actual_index < len(actual):
        expected_event = _entry(expected, expected_index)
        actual_event = _entry(actual, actual_index)
        if expected_event is None:
            assert actual_event is not None
            return IntentionDifference(
                RunDifferenceKind.ADDED,
                _intention_key(actual_event),
                None,
                actual_event,
            )
        if actual_event is None:
            return IntentionDifference(
                RunDifferenceKind.REMOVED,
                _intention_key(expected_event),
                expected_event,
                None,
            )
        expected_key = _intention_key(expected_event)
        actual_key = _intention_key(actual_event)
        if _intention_key_order(expected_key) < _intention_key_order(actual_key):
            return IntentionDifference(
                RunDifferenceKind.REMOVED, expected_key, expected_event, None
            )
        if _intention_key_order(expected_key) > _intention_key_order(actual_key):
            return IntentionDifference(RunDifferenceKind.ADDED, actual_key, None, actual_event)
        if not _same_emitted_intention(expected_event, actual_event):
            return IntentionDifference(
                RunDifferenceKind.CHANGED,
                expected_key,
                expected_event,
                actual_event,
            )
        expected_index += 1
        actual_index += 1
    return None


def _policy_evaluation_key(event: PolicyEvaluated) -> PolicyEvaluationComparisonKey:
    return PolicyEvaluationComparisonKey(
        event.header.tick,
        event.validation.evaluation.entity_id,
    )


def _intention_key(event: IntentionEmitted) -> IntentionComparisonKey:
    origin = event.candidate.origin
    return IntentionComparisonKey(
        origin.creation_tick,
        origin.issuer_entity_id,
        origin.policy_order,
    )


def _evaluation_key_order(key: PolicyEvaluationComparisonKey) -> tuple[int, int]:
    return (key.tick, key.entity_id.value)


def _intention_key_order(key: IntentionComparisonKey) -> tuple[int, int, int]:
    return (key.tick, key.issuer_entity_id.value, key.policy_order)


def _same_emitted_intention(expected: IntentionEmitted, actual: IntentionEmitted) -> bool:
    return (
        _same_origin_without_allocation(expected.candidate.origin, actual.candidate.origin)
        and expected.candidate.intention == actual.candidate.intention
    )


def _same_origin_without_allocation(expected: IntentionOrigin, actual: IntentionOrigin) -> bool:
    return (
        expected.issuer_entity_id == actual.issuer_entity_id
        and expected.source_expression_id == actual.source_expression_id
        and expected.source_span == actual.source_span
        and expected.policy_order == actual.policy_order
        and expected.creation_tick == actual.creation_tick
        and expected.kind is actual.kind
    )


def _entry[T](entries: tuple[T, ...], index: int) -> T | None:
    if index == len(entries):
        return None
    return entries[index]


def _has_adjacent_duplicates[T](values: tuple[T, ...]) -> bool:
    return any(first == second for first, second in zip(values, values[1:], strict=False))


def _require_difference_records[T](
    kind: RunDifferenceKind,
    expected: T | None,
    actual: T | None,
    record_type: type[T],
    label: str,
) -> None:
    if expected is not None and not isinstance(expected, record_type):
        raise ValueError(f"{label} difference expected record is invalid")
    if actual is not None and not isinstance(actual, record_type):
        raise ValueError(f"{label} difference actual record is invalid")
    if kind is RunDifferenceKind.ADDED and (expected is not None or actual is None):
        raise ValueError(f"added {label} difference requires only an actual record")
    if kind is RunDifferenceKind.REMOVED and (expected is None or actual is not None):
        raise ValueError(f"removed {label} difference requires only an expected record")
    if kind is RunDifferenceKind.CHANGED and (expected is None or actual is None):
        raise ValueError(f"changed {label} difference requires both records")
