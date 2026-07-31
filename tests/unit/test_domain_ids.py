from __future__ import annotations

import pytest

from kiwi.domain.ids import (
    FIRST_DYNAMIC_ID,
    MAX_STABLE_ID,
    ContactId,
    CoverId,
    EntityId,
    EventId,
    IdAllocator,
    IdKind,
    IntentionId,
    MessageId,
    ObjectiveId,
    OperativeId,
    PolicyInvocationId,
    ProjectileId,
    StableId,
    TraceNodeId,
    canonical_id_value,
)


def test_authority_ids_are_typed_and_value_based() -> None:
    assert EntityId(3) == EntityId(3)
    assert ContactId(3) == ContactId(3)
    assert not isinstance(EntityId(3), ContactId)
    assert canonical_id_value(EntityId(3)) == 3


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: EntityId(0), "positive"),
        (lambda: EntityId(-1), "positive"),
        (lambda: EntityId(MAX_STABLE_ID + 1), "signed"),
        (lambda: EntityId(True), "integer"),
        (lambda: canonical_id_value(3), "stable ID"),  # type: ignore[arg-type]
        (lambda: IdAllocator((FIRST_DYNAMIC_ID,)), "one counter"),
        (lambda: IdAllocator([]), "immutable tuple"),  # type: ignore[arg-type]
    ),
)
def test_authority_ids_and_allocator_state_reject_invalid_values(
    factory: object,
    message: str,
) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def test_id_allocator_is_immutable_type_local_and_deterministic() -> None:
    initial = IdAllocator()
    entity_one, after_entity_one = initial.allocate_entity()
    projectile_one, after_projectile_one = after_entity_one.allocate_projectile()
    entity_two, after_entity_two = after_projectile_one.allocate_entity()

    assert entity_one == EntityId(1)
    assert projectile_one == ProjectileId(1)
    assert entity_two == EntityId(2)
    assert initial == IdAllocator()
    assert after_entity_two.next_ids[int(IdKind.ENTITY)] == 3
    assert after_entity_two.next_ids[int(IdKind.PROJECTILE)] == 2

    replay_entity, replay_after_entity = IdAllocator().allocate_entity()
    replay_projectile, replay_after_projectile = replay_after_entity.allocate_projectile()
    replay_entity_two, replay_final = replay_after_projectile.allocate_entity()
    assert (replay_entity, replay_projectile, replay_entity_two, replay_final) == (
        entity_one,
        projectile_one,
        entity_two,
        after_entity_two,
    )


def test_id_allocator_exposes_one_typed_entry_point_per_authority_family() -> None:
    allocator = IdAllocator()
    allocated = (
        allocator.allocate_entity()[0],
        allocator.allocate_operative()[0],
        allocator.allocate_contact()[0],
        allocator.allocate_cover()[0],
        allocator.allocate_projectile()[0],
        allocator.allocate_intention()[0],
        allocator.allocate_event()[0],
        allocator.allocate_policy_invocation()[0],
        allocator.allocate_trace_node()[0],
        allocator.allocate_objective()[0],
        allocator.allocate_message()[0],
    )

    assert tuple(type(value) for value in allocated) == (
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
    )
    assert all(canonical_id_value(value) == FIRST_DYNAMIC_ID for value in allocated)


def test_id_allocator_fails_deterministically_when_a_type_counter_is_exhausted() -> None:
    exhausted = IdAllocator((MAX_STABLE_ID + 1,) + (FIRST_DYNAMIC_ID,) * (len(IdKind) - 1))

    with pytest.raises(ValueError, match="entity ID allocation exhausted"):
        exhausted.allocate_entity()


def test_stable_id_alias_is_closed() -> None:
    stable_id: StableId = EntityId(1)
    assert canonical_id_value(stable_id) == 1
