"""Immutable, persistable policy memory keyed by canonical entity ID."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.ids import EntityId
from kiwi.dsl.runtime_values import (
    MAX_RUNTIME_STRING_BYTES,
    BooleanValue,
    IntegerValue,
    ListValue,
    OptionNoneValue,
    OptionSomeValue,
    QuantityValue,
    RecordValue,
    RuntimeValue,
    StringValue,
    UnitValue,
)

MAX_POLICY_MEMORY_DEPTH = 64


@dataclass(frozen=True, slots=True)
class EntityPolicyMemory:
    """One entity's validated data-only policy memory record."""

    entity_id: EntityId
    value: RecordValue

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("entity policy memory requires an entity ID")
        if not isinstance(self.value, RecordValue):
            raise ValueError("entity policy memory requires a record value")
        if not is_persistable_memory_value(self.value):
            raise ValueError("entity policy memory must contain only persistable data values")


@dataclass(frozen=True, slots=True)
class PolicyMemoryStore:
    """An immutable entity-ID-ordered sparse policy-memory mapping."""

    entries: tuple[EntityPolicyMemory, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.entries, tuple):
            raise ValueError("policy memory entries must be an immutable tuple")
        previous_id = 0
        for entry in self.entries:
            if not isinstance(entry, EntityPolicyMemory):
                raise ValueError("policy memory entries must be entity policy memories")
            if entry.entity_id.value <= previous_id:
                raise ValueError("policy memory entries must be unique and entity-ID ordered")
            previous_id = entry.entity_id.value

    def memory_for(self, entity_id: EntityId) -> RecordValue | None:
        """Return one entity's memory, or `None` before its policy is initialised."""
        if not isinstance(entity_id, EntityId):
            raise ValueError("policy memory lookup requires an entity ID")
        for entry in self.entries:
            if entry.entity_id == entity_id:
                return entry.value
        return None

    def with_memory(self, entity_id: EntityId, value: RecordValue) -> PolicyMemoryStore:
        """Store one validated record without changing the original mapping."""
        entry = EntityPolicyMemory(entity_id, value)
        retained = tuple(item for item in self.entries if item.entity_id != entity_id)
        return PolicyMemoryStore(
            tuple(sorted((*retained, entry), key=lambda item: item.entity_id.value))
        )


def is_persistable_memory_value(value: RuntimeValue, depth: int = 0) -> bool:
    """Return whether a closed DSL value can safely enter canonical authority state."""
    if depth >= MAX_POLICY_MEMORY_DEPTH:
        return False
    if isinstance(
        value,
        (
            IntegerValue,
            BooleanValue,
            UnitValue,
            StringValue,
            QuantityValue,
            OptionNoneValue,
        ),
    ):
        return True
    if isinstance(value, OptionSomeValue):
        return is_persistable_memory_value(value.value, depth + 1)
    if isinstance(value, ListValue):
        return all(is_persistable_memory_value(item, depth + 1) for item in value.values)
    if isinstance(value, RecordValue):
        return (
            len(value.type_name.encode("utf-8")) <= MAX_RUNTIME_STRING_BYTES
            and all(
                len(field_name.encode("utf-8")) <= MAX_RUNTIME_STRING_BYTES
                for field_name in value.field_names
            )
            and all(is_persistable_memory_value(item, depth + 1) for item in value.values)
        )
    return False
