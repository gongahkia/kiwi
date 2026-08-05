from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits, WorldVector
from kiwi.domain.ids import CoverId, EventId, ProjectileId
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.sim.events import EventHeader, ProjectileImpacted
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.intentions import IntentionKind, IntentionOrigin
from kiwi.sim.projectile_impacts import ProjectileImpact
from kiwi.sim.projectile_sweeps import ProjectileCollision, ProjectileCollisionKind
from kiwi.sim.projectiles import Projectile, ProjectileProvenance, ProjectileStore
from kiwi.sim.snapshot import (
    PresentationImpact,
    PresentationPoint,
    PresentationProjectile,
    PresentationSnapshot,
    build_presentation_projectile_impacts,
    build_presentation_snapshot,
)
from kiwi.sim.state import MissionState, add_entity
from kiwi.sim.weapons import AimState, AimStore, SuppressionState, SuppressionStore

_SOURCE = SourceFile(SourceFileId("combat-presentation-test.dtr"), "")


def test_combat_presentation_copies_live_state_and_current_impact_events() -> None:
    state, owner = add_entity(MissionState(), _position(0, 0))
    projectile_id, allocator = state.id_allocator.allocate_projectile()
    intention_id, allocator = allocator.allocate_intention()
    invocation_id, allocator = allocator.allocate_policy_invocation()
    projectile = Projectile(
        projectile_id,
        owner.entity_id,
        ProjectileProvenance(
            IntentionOrigin(
                intention_id,
                owner.entity_id,
                invocation_id,
                ExpressionId(0),
                _SOURCE.span(ByteOffset(0), ByteOffset(0)),
                0,
                0,
                IntentionKind.FIRE,
            )
        ),
        _position(100, 0),
        WorldVector(WorldSubunits(1_000), WorldSubunits(0)),
        3,
    )
    state = replace(
        state,
        id_allocator=allocator,
        aim_states=AimStore((AimState(owner.entity_id, 6_000),)),
        suppressions=SuppressionStore((SuppressionState(owner.entity_id, 2_500),)),
        projectiles=ProjectileStore((projectile,)),
    )
    impact = ProjectileImpact(
        state.tick,
        projectile,
        ProjectileCollision(ProjectileCollisionKind.COVER, CoverId(1), 0, _position(500, 0)),
    )
    event = ProjectileImpacted(EventHeader(event_id=EventId(2), tick=0), impact)
    state_hash = hash_canonical_state(state)

    snapshot = build_presentation_snapshot(state, projectile_events=(event,))

    assert hash_canonical_state(state) == state_hash
    assert snapshot.operatives[0].aim_quality_basis_points == 6_000
    assert snapshot.operatives[0].suppression_basis_points == 2_500
    assert snapshot.projectiles == (PresentationProjectile(1, 1, PresentationPoint(100.0, 0.0, 0)),)
    assert snapshot.impacts == (PresentationImpact(1, PresentationPoint(500.0, 0.0, 0), "cover"),)
    second_impact = replace(impact, projectile=replace(projectile, projectile_id=ProjectileId(2)))
    preceding_second_impact = ProjectileImpacted(
        EventHeader(event_id=EventId(1), tick=0), second_impact
    )

    assert tuple(
        marker.projectile_id
        for marker in build_presentation_projectile_impacts((event, preceding_second_impact))
    ) == (1, 2)


def test_combat_presentation_rejects_mutable_events_and_orphan_projectiles() -> None:
    with pytest.raises(TypeError, match="immutable canonical events"):
        build_presentation_projectile_impacts([])  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="owners"):
        PresentationSnapshot(
            0,
            "active",
            None,
            (),
            projectiles=(PresentationProjectile(1, 1, PresentationPoint(0.0, 0.0, 0)),),
        )


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))
