from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldSubunits, WorldVector
from kiwi.domain.ids import EntityId, IntentionId, PolicyInvocationId, ProjectileId
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.sim.hashing import decode_canonical_state, encode_canonical_state, hash_canonical_state
from kiwi.sim.intentions import IntentionKind, IntentionOrigin
from kiwi.sim.projectiles import Projectile, ProjectileProvenance, ProjectileStore
from kiwi.sim.state import MissionState, add_entity


def test_projectile_store_is_canonical_and_lookup_is_explicit() -> None:
    first = _projectile(ProjectileId(1), EntityId(1), IntentionId(1))
    second = _projectile(ProjectileId(2), EntityId(1), IntentionId(2))
    store = ProjectileStore((first, second))

    assert store.projectile_for(ProjectileId(2)) == second
    assert store.projectile_for(ProjectileId(3)) is None
    with pytest.raises(ValueError, match="projectile-ID ordered"):
        ProjectileStore((second, first))


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: replace(
                _projectile(ProjectileId(1), EntityId(1), IntentionId(1)),
                velocity=WorldVector(WorldSubunits(0), WorldSubunits(0)),
            ),
            "velocity",
        ),
        (lambda: _projectile(ProjectileId(1), EntityId(1), IntentionId(1), 0), "lifetime"),
    ),
)
def test_projectiles_reject_invalid_values(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def test_projectile_authority_state_round_trips_and_hashes() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(0), WorldSubunits(0)))
    projectile_id, allocator = state.id_allocator.allocate_projectile()
    intention_id, allocator = allocator.allocate_intention()
    _, allocator = allocator.allocate_policy_invocation()
    projectile = _projectile(projectile_id, entity.entity_id, intention_id)
    state = replace(state, id_allocator=allocator, projectiles=ProjectileStore((projectile,)))

    decoded = decode_canonical_state(encode_canonical_state(state))

    assert decoded == state
    assert isinstance(decoded, MissionState)
    assert decoded.projectiles.entries[0].source_intention == projectile.source_intention
    changed_origin = replace(projectile.source_intention, source_expression_id=ExpressionId(1))
    assert hash_canonical_state(state) != hash_canonical_state(
        replace(state, projectiles=ProjectileStore())
    )
    assert hash_canonical_state(state) != hash_canonical_state(
        replace(
            state,
            projectiles=ProjectileStore(
                (replace(projectile, provenance=ProjectileProvenance(changed_origin)),)
            ),
        )
    )


def test_mission_state_rejects_unallocated_or_orphan_projectiles() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(0), WorldSubunits(0)))
    unallocated = _projectile(ProjectileId(1), entity.entity_id, IntentionId(1))

    with pytest.raises(ValueError, match="projectile IDs must be allocated"):
        replace(state, projectiles=ProjectileStore((unallocated,)))
    projectile_id, allocator = state.id_allocator.allocate_projectile()
    with pytest.raises(ValueError, match="source intention IDs must be allocated"):
        replace(
            state,
            id_allocator=allocator,
            projectiles=ProjectileStore(
                (_projectile(projectile_id, entity.entity_id, IntentionId(1)),)
            ),
        )
    intention_id, allocator = allocator.allocate_intention()
    with pytest.raises(ValueError, match="projectiles must belong"):
        replace(
            state,
            id_allocator=allocator,
            projectiles=ProjectileStore((_projectile(projectile_id, EntityId(2), intention_id),)),
        )


def _projectile(
    projectile_id: ProjectileId,
    owner_entity_id: EntityId,
    source_intention_id: IntentionId,
    remaining_ticks: int = 3,
) -> Projectile:
    return Projectile(
        projectile_id,
        owner_entity_id,
        ProjectileProvenance(
            IntentionOrigin(
                source_intention_id,
                owner_entity_id,
                PolicyInvocationId(1),
                ExpressionId(0),
                _SOURCE.span(ByteOffset(0), ByteOffset(0)),
                0,
                0,
                IntentionKind.FIRE,
            )
        ),
        WorldPosition(WorldSubunits(-25), WorldSubunits(50), ElevationLayer(2)),
        WorldVector(WorldSubunits(400), WorldSubunits(-125)),
        remaining_ticks,
    )


_SOURCE = SourceFile(SourceFileId("projectile-test.dtr"), "")
