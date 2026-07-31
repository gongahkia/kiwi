"""Typed stable identifiers and deterministic allocation state."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from enum import IntEnum
from typing import TypeVar

MAX_STABLE_ID = (1 << 63) - 1
FIRST_DYNAMIC_ID = 1


def _validate_stable_id(value: int, label: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"{label} must be an integer")
    if not FIRST_DYNAMIC_ID <= value <= MAX_STABLE_ID:
        raise ValueError(f"{label} must fit positive signed 64-bit range")


@dataclass(frozen=True, slots=True)
class EntityId:
    """The stable identity of a world entity."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "entity ID")


@dataclass(frozen=True, slots=True)
class OperativeId:
    """The stable identity of an operative."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "operative ID")


@dataclass(frozen=True, slots=True)
class ContactId:
    """The stable identity of a local contact estimate."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "contact ID")


@dataclass(frozen=True, slots=True)
class CoverId:
    """The stable identity of one cover feature."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "cover ID")


@dataclass(frozen=True, slots=True)
class ProjectileId:
    """The stable identity of one projectile."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "projectile ID")


@dataclass(frozen=True, slots=True)
class IntentionId:
    """The stable identity of one policy intention."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "intention ID")


@dataclass(frozen=True, slots=True)
class EventId:
    """The stable identity of one authoritative event."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "event ID")


@dataclass(frozen=True, slots=True)
class PolicyInvocationId:
    """The stable identity of one policy VM invocation."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "policy invocation ID")


@dataclass(frozen=True, slots=True)
class TraceNodeId:
    """The stable identity of one causal trace node."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "trace node ID")


@dataclass(frozen=True, slots=True)
class ObjectiveId:
    """The stable identity of one mission objective."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "objective ID")


@dataclass(frozen=True, slots=True)
class MessageId:
    """The stable identity of one message."""

    value: int

    def __post_init__(self) -> None:
        _validate_stable_id(self.value, "message ID")


StableId = (
    EntityId
    | OperativeId
    | ContactId
    | CoverId
    | ProjectileId
    | IntentionId
    | EventId
    | PolicyInvocationId
    | TraceNodeId
    | ObjectiveId
    | MessageId
)


class IdKind(IntEnum):
    """Canonical slots for per-type dynamic ID counters."""

    ENTITY = 0
    OPERATIVE = 1
    CONTACT = 2
    COVER = 3
    PROJECTILE = 4
    INTENTION = 5
    EVENT = 6
    POLICY_INVOCATION = 7
    TRACE_NODE = 8
    OBJECTIVE = 9
    MESSAGE = 10


_INITIAL_NEXT_IDS = (FIRST_DYNAMIC_ID,) * len(IdKind)
_IdType = TypeVar("_IdType", bound=StableId)


@dataclass(frozen=True, slots=True)
class IdAllocator:
    """Immutable deterministic counter state for all run-local authority IDs."""

    next_ids: tuple[int, ...] = _INITIAL_NEXT_IDS

    def __post_init__(self) -> None:
        if not isinstance(self.next_ids, tuple):
            raise ValueError("ID allocator counters must be an immutable tuple")
        if len(self.next_ids) != len(IdKind):
            raise ValueError("ID allocator must contain one counter for every ID kind")
        for next_id in self.next_ids:
            if not isinstance(next_id, int) or isinstance(next_id, bool):
                raise ValueError("ID allocator counters must be integers")
            if not FIRST_DYNAMIC_ID <= next_id <= MAX_STABLE_ID + 1:
                raise ValueError("ID allocator counters must fit positive signed 64-bit range")

    def allocate_entity(self) -> tuple[EntityId, IdAllocator]:
        return self._allocate(IdKind.ENTITY, EntityId)

    def allocate_operative(self) -> tuple[OperativeId, IdAllocator]:
        return self._allocate(IdKind.OPERATIVE, OperativeId)

    def allocate_contact(self) -> tuple[ContactId, IdAllocator]:
        return self._allocate(IdKind.CONTACT, ContactId)

    def allocate_cover(self) -> tuple[CoverId, IdAllocator]:
        return self._allocate(IdKind.COVER, CoverId)

    def allocate_projectile(self) -> tuple[ProjectileId, IdAllocator]:
        return self._allocate(IdKind.PROJECTILE, ProjectileId)

    def allocate_intention(self) -> tuple[IntentionId, IdAllocator]:
        return self._allocate(IdKind.INTENTION, IntentionId)

    def allocate_event(self) -> tuple[EventId, IdAllocator]:
        return self._allocate(IdKind.EVENT, EventId)

    def allocate_policy_invocation(self) -> tuple[PolicyInvocationId, IdAllocator]:
        return self._allocate(IdKind.POLICY_INVOCATION, PolicyInvocationId)

    def allocate_trace_node(self) -> tuple[TraceNodeId, IdAllocator]:
        return self._allocate(IdKind.TRACE_NODE, TraceNodeId)

    def allocate_objective(self) -> tuple[ObjectiveId, IdAllocator]:
        return self._allocate(IdKind.OBJECTIVE, ObjectiveId)

    def allocate_message(self) -> tuple[MessageId, IdAllocator]:
        return self._allocate(IdKind.MESSAGE, MessageId)

    def _allocate(
        self,
        kind: IdKind,
        factory: Callable[[int], _IdType],
    ) -> tuple[_IdType, IdAllocator]:
        index = int(kind)
        next_id = self.next_ids[index]
        if next_id > MAX_STABLE_ID:
            raise ValueError(f"{kind.name.lower()} ID allocation exhausted")
        updated_next_ids = self.next_ids[:index] + (next_id + 1,) + self.next_ids[index + 1 :]
        return factory(next_id), IdAllocator(updated_next_ids)


def canonical_id_value(value: StableId) -> int:
    """Return an explicit canonical ordering key for same-kind IDs."""
    if not isinstance(
        value,
        (
            EntityId,
            OperativeId,
            ContactId,
            CoverId,
            ProjectileId,
            IntentionId,
            EventId,
            PolicyInvocationId,
            TraceNodeId,
            ObjectiveId,
            MessageId,
        ),
    ):
        raise ValueError("canonical ID key requires a stable ID")
    return value.value
