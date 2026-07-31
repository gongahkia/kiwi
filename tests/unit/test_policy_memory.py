from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EntityId
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.runtime_values import FunctionValue, IntegerValue, RecordValue, StringValue
from kiwi.sim.memory import EntityPolicyMemory, PolicyMemoryStore
from kiwi.sim.state import MissionState, add_entity


def _memory(label: str) -> RecordValue:
    return RecordValue("Memory", ("label",), (StringValue(label),))


def test_policy_memory_store_is_immutable_entity_ordered_and_replaceable() -> None:
    initial = PolicyMemoryStore()
    with_second = initial.with_memory(EntityId(2), _memory("second"))
    updated = with_second.with_memory(EntityId(1), _memory("first"))
    replaced = updated.with_memory(EntityId(2), _memory("updated"))

    assert initial.entries == ()
    assert tuple(entry.entity_id for entry in updated.entries) == (EntityId(1), EntityId(2))
    assert updated.memory_for(EntityId(1)) == _memory("first")
    assert updated.memory_for(EntityId(3)) is None
    assert replaced.memory_for(EntityId(2)) == _memory("updated")


def test_policy_memory_rejects_callables_and_noncanonical_entries() -> None:
    callable_memory = RecordValue("Memory", ("callback",), (FunctionValue(FunctionId(0)),))

    with pytest.raises(ValueError, match="persistable"):
        EntityPolicyMemory(EntityId(1), callable_memory)
    with pytest.raises(ValueError, match="entity-ID ordered"):
        PolicyMemoryStore(
            (
                EntityPolicyMemory(EntityId(2), _memory("second")),
                EntityPolicyMemory(EntityId(1), _memory("first")),
            )
        )


def test_mission_state_requires_memory_entries_to_belong_to_entities() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(1), WorldSubunits(2)))
    memory = PolicyMemoryStore().with_memory(entity.entity_id, _memory("ready"))

    assert replace(state, policy_memory=memory).policy_memory == memory
    with pytest.raises(ValueError, match="belong to mission entities"):
        MissionState(policy_memory=PolicyMemoryStore().with_memory(EntityId(1), _memory("orphan")))


def test_policy_memory_requires_record_values() -> None:
    with pytest.raises(ValueError, match="record value"):
        EntityPolicyMemory(EntityId(1), IntegerValue(1))  # type: ignore[arg-type]
