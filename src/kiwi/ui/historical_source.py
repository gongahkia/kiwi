"""Immutable historical-source panes bound only to replay source archives."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EntityId
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.source import SourceFile, SourceSpan
from kiwi.replay.source_archive import (
    HistoricalPolicySource,
    ReplaySourceArchive,
)
from kiwi.sim.policy_versions import PolicyVersion


class HistoricalSourceUnavailableCode(StrEnum):
    POLICY_NOT_RETAINED = "policy_not_retained"
    EXPRESSION_NOT_RETAINED = "expression_not_retained"


@dataclass(frozen=True, slots=True)
class HistoricalSourceUnavailable:
    code: HistoricalSourceUnavailableCode
    entity_id: EntityId
    expression_id: ExpressionId | None

    def __post_init__(self) -> None:
        if not isinstance(self.code, HistoricalSourceUnavailableCode):
            raise TypeError("historical source unavailable result requires a code")
        if not isinstance(self.entity_id, EntityId):
            raise TypeError("historical source unavailable result requires an entity ID")
        if self.expression_id is not None and not isinstance(self.expression_id, ExpressionId):
            raise TypeError("historical source unavailable expression ID is invalid")


@dataclass(frozen=True, slots=True)
class HistoricalSourcePane:
    entity_id: EntityId
    policy_version: PolicyVersion
    source: SourceFile
    expression_id: ExpressionId | None
    highlighted_spans: tuple[SourceSpan, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise TypeError("historical source pane requires an entity ID")
        if not isinstance(self.policy_version, PolicyVersion):
            raise TypeError("historical source pane requires a policy version")
        if not isinstance(self.source, SourceFile):
            raise TypeError("historical source pane requires a source file")
        if self.expression_id is not None and not isinstance(self.expression_id, ExpressionId):
            raise TypeError("historical source pane expression ID is invalid")
        if not isinstance(self.highlighted_spans, tuple) or any(
            not isinstance(span, SourceSpan) for span in self.highlighted_spans
        ):
            raise TypeError("historical source highlights must be immutable source spans")
        keys = tuple((span.start.value, span.end.value) for span in self.highlighted_spans)
        if keys != tuple(sorted(keys)) or len(set(keys)) != len(keys):
            raise ValueError("historical source highlights must be unique and source ordered")
        for span in self.highlighted_spans:
            self.source.positions_of(span)
        if self.expression_id is None and self.highlighted_spans:
            raise ValueError("historical source highlights require a selected expression")
        if self.expression_id is not None and not self.highlighted_spans:
            raise ValueError("historical source expression requires retained highlights")


type HistoricalSourcePaneResult = HistoricalSourcePane | HistoricalSourceUnavailable


def historical_source_pane(
    archive: ReplaySourceArchive,
    entity_id: EntityId,
    expression_id: ExpressionId | None = None,
) -> HistoricalSourcePaneResult:
    """Return archive-bound source and optional exact source-map expression spans."""
    if not isinstance(archive, ReplaySourceArchive):
        raise TypeError("historical source pane requires a replay source archive")
    if not isinstance(entity_id, EntityId):
        raise TypeError("historical source pane requires an entity ID")
    if expression_id is not None and not isinstance(expression_id, ExpressionId):
        raise TypeError("historical source pane expression ID is invalid")
    policy = _policy_for_entity(archive, entity_id)
    if policy is None:
        return HistoricalSourceUnavailable(
            HistoricalSourceUnavailableCode.POLICY_NOT_RETAINED,
            entity_id,
            expression_id,
        )
    source = _source_for_policy(archive, policy)
    spans = _expression_spans(policy, expression_id)
    if expression_id is not None and not spans:
        return HistoricalSourceUnavailable(
            HistoricalSourceUnavailableCode.EXPRESSION_NOT_RETAINED,
            entity_id,
            expression_id,
        )
    return HistoricalSourcePane(entity_id, policy.version, source, expression_id, spans)


def _policy_for_entity(
    archive: ReplaySourceArchive,
    entity_id: EntityId,
) -> HistoricalPolicySource | None:
    for policy in archive.policies:
        if policy.entity_id == entity_id:
            return policy
    return None


def _source_for_policy(
    archive: ReplaySourceArchive,
    policy: HistoricalPolicySource,
) -> SourceFile:
    source_file_id = policy.bytecode.header.source_file_id
    for historical_source in archive.sources:
        if historical_source.source.file_id == source_file_id:
            return historical_source.source
    raise AssertionError("validated source archive has no policy source")


def _expression_spans(
    policy: HistoricalPolicySource,
    expression_id: ExpressionId | None,
) -> tuple[SourceSpan, ...]:
    if expression_id is None:
        return ()
    spans = sorted(
        (
            entry.span
            for entry in policy.bytecode.source_map.entries
            if entry.expression_id == expression_id
        ),
        key=lambda span: (span.start.value, span.end.value),
    )
    unique: list[SourceSpan] = []
    for span in spans:
        if not unique or span != unique[-1]:
            unique.append(span)
    return tuple(unique)
