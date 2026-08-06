"""Canonical automatic retrieval and full-squad extraction objective state."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import TYPE_CHECKING

from kiwi.domain.geometry import WorldRectangle
from kiwi.domain.ids import EntityId, EventId, ObjectiveId

if TYPE_CHECKING:
    from kiwi.sim.state import EntityState


class ObjectiveStatus(StrEnum):
    """The bounded lifecycle of one retrieval-and-extraction objective."""

    ACTIVE = "active"
    RETRIEVED = "retrieved"
    EXTRACTED = "extracted"


@dataclass(frozen=True, slots=True)
class RetrievalObjective:
    """One objective retrieved by the first listed entity entering its target region."""

    objective_id: ObjectiveId
    retrieval_area: WorldRectangle
    extraction_area: WorldRectangle
    required_entity_ids: tuple[EntityId, ...]
    status: ObjectiveStatus = ObjectiveStatus.ACTIVE
    retrieved_by: EntityId | None = None
    retrieval_event_id: EventId | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.objective_id, ObjectiveId):
            raise ValueError("objective requires an objective ID")
        if not isinstance(self.retrieval_area, WorldRectangle):
            raise ValueError("objective retrieval area must be a world rectangle")
        if not isinstance(self.extraction_area, WorldRectangle):
            raise ValueError("objective extraction area must be a world rectangle")
        if not isinstance(self.required_entity_ids, tuple) or not self.required_entity_ids:
            raise ValueError("objective requires immutable required entity IDs")
        previous_id = 0
        for entity_id in self.required_entity_ids:
            if not isinstance(entity_id, EntityId) or entity_id.value <= previous_id:
                raise ValueError("objective required entity IDs must be ascending and unique")
            previous_id = entity_id.value
        if not isinstance(self.status, ObjectiveStatus):
            raise ValueError("objective requires a status")
        if self.status is ObjectiveStatus.ACTIVE and (
            self.retrieved_by is not None or self.retrieval_event_id is not None
        ):
            raise ValueError("active objective cannot have retrieval provenance")
        if (
            self.status is not ObjectiveStatus.ACTIVE
            and self.retrieved_by not in self.required_entity_ids
        ):
            raise ValueError("completed objective requires one listed retriever")
        if self.status is not ObjectiveStatus.ACTIVE and not isinstance(
            self.retrieval_event_id, EventId
        ):
            raise ValueError("completed objective requires a retrieval event ID")


@dataclass(frozen=True, slots=True)
class ObjectiveStore:
    """An immutable objective-ID-ordered mission objective collection."""

    entries: tuple[RetrievalObjective, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.entries, tuple):
            raise ValueError("objective store entries must be an immutable tuple")
        previous_id = 0
        for objective in self.entries:
            if (
                not isinstance(objective, RetrievalObjective)
                or objective.objective_id.value <= previous_id
            ):
                raise ValueError("objective store entries must be objective-ID ordered")
            previous_id = objective.objective_id.value


def retrieval_candidate(
    objective: RetrievalObjective, entities: tuple[EntityState, ...]
) -> EntityId | None:
    """Return the lowest-ID listed entity currently in an active retrieval area."""
    if not isinstance(objective, RetrievalObjective) or not isinstance(entities, tuple):
        raise TypeError("objective retrieval requires an objective and immutable entities")
    if objective.status is not ObjectiveStatus.ACTIVE:
        return None
    for entity in entities:
        if (
            entity.entity_id in objective.required_entity_ids
            and objective.retrieval_area.contains_position(entity.position)
        ):
            return entity.entity_id
    return None


def extraction_ready(objective: RetrievalObjective, entities: tuple[EntityState, ...]) -> bool:
    """Return whether every required entity is in a previously retrieved objective's exit area."""
    if not isinstance(objective, RetrievalObjective) or not isinstance(entities, tuple):
        raise TypeError("objective extraction requires an objective and immutable entities")
    if objective.status is not ObjectiveStatus.RETRIEVED:
        return False
    positions = tuple((entity.entity_id, entity.position) for entity in entities)
    return all(
        any(
            entity_id == required_id and objective.extraction_area.contains_position(position)
            for entity_id, position in positions
        )
        for required_id in objective.required_entity_ids
    )


def retrieved_objective(
    objective: RetrievalObjective, retriever: EntityId, event_id: EventId
) -> RetrievalObjective:
    """Return an active objective after one canonical retrieval transition."""
    if not isinstance(objective, RetrievalObjective):
        raise TypeError("objective retrieval transition requires an objective")
    if objective.status is not ObjectiveStatus.ACTIVE:
        raise ValueError("only active objectives can be retrieved")
    if retriever not in objective.required_entity_ids or not isinstance(event_id, EventId):
        raise ValueError("objective retrieval requires a listed entity and event ID")
    return RetrievalObjective(
        objective.objective_id,
        objective.retrieval_area,
        objective.extraction_area,
        objective.required_entity_ids,
        ObjectiveStatus.RETRIEVED,
        retriever,
        event_id,
    )


def extracted_objective(objective: RetrievalObjective) -> RetrievalObjective:
    """Return a retrieved objective after the full squad's canonical extraction transition."""
    if not isinstance(objective, RetrievalObjective):
        raise TypeError("objective extraction transition requires an objective")
    if objective.status is not ObjectiveStatus.RETRIEVED:
        raise ValueError("only retrieved objectives can be extracted")
    return RetrievalObjective(
        objective.objective_id,
        objective.retrieval_area,
        objective.extraction_area,
        objective.required_entity_ids,
        ObjectiveStatus.EXTRACTED,
        objective.retrieved_by,
        objective.retrieval_event_id,
    )


def replace_objective(store: ObjectiveStore, replacement: RetrievalObjective) -> ObjectiveStore:
    """Replace one existing objective without changing canonical objective ordering."""
    if not isinstance(store, ObjectiveStore) or not isinstance(replacement, RetrievalObjective):
        raise TypeError("objective replacement requires an objective store and objective")
    entries = tuple(
        replacement if objective.objective_id == replacement.objective_id else objective
        for objective in store.entries
    )
    if entries == store.entries:
        raise ValueError("objective replacement requires an existing objective ID")
    return ObjectiveStore(entries)
