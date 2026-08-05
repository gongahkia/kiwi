"""Canonical point-projectile authority state before physical resolution."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.geometry import WorldPosition, WorldVector
from kiwi.domain.ids import EntityId, IntentionId, ProjectileId
from kiwi.sim.limits import MAX_AUTHORITY_TICK


@dataclass(frozen=True, slots=True)
class Projectile:
    """One live point projectile with a fixed exact per-tick velocity."""

    projectile_id: ProjectileId
    owner_entity_id: EntityId
    source_intention_id: IntentionId
    position: WorldPosition
    velocity: WorldVector
    remaining_ticks: int

    def __post_init__(self) -> None:
        if not isinstance(self.projectile_id, ProjectileId):
            raise ValueError("projectile requires a projectile ID")
        if not isinstance(self.owner_entity_id, EntityId):
            raise ValueError("projectile requires an owner entity ID")
        if not isinstance(self.source_intention_id, IntentionId):
            raise ValueError("projectile requires a source intention ID")
        if not isinstance(self.position, WorldPosition):
            raise ValueError("projectile requires a world position")
        if not isinstance(self.velocity, WorldVector):
            raise ValueError("projectile requires a world vector velocity")
        if self.velocity.dx.value == 0 and self.velocity.dy.value == 0:
            raise ValueError("projectile velocity must be nonzero")
        if not isinstance(self.remaining_ticks, int) or isinstance(self.remaining_ticks, bool):
            raise ValueError("projectile lifetime must be an integer")
        if not 1 <= self.remaining_ticks <= MAX_AUTHORITY_TICK:
            raise ValueError("projectile lifetime is outside the configured range")


@dataclass(frozen=True, slots=True)
class ProjectileStore:
    """An immutable projectile-ID-ordered live-projectile store."""

    entries: tuple[Projectile, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.entries, tuple):
            raise ValueError("projectile store entries must be an immutable tuple")
        previous_projectile_id = 0
        for entry in self.entries:
            if not isinstance(entry, Projectile):
                raise ValueError("projectile store entries must be projectiles")
            if entry.projectile_id.value <= previous_projectile_id:
                raise ValueError("projectile store entries must be projectile-ID ordered")
            previous_projectile_id = entry.projectile_id.value

    def projectile_for(self, projectile_id: ProjectileId) -> Projectile | None:
        """Return one projectile without relying on unordered lookup."""
        if not isinstance(projectile_id, ProjectileId):
            raise ValueError("projectile lookup requires a projectile ID")
        for entry in self.entries:
            if entry.projectile_id == projectile_id:
                return entry
        return None
