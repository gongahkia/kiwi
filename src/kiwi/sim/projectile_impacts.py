"""Canonical projectile advancement and collision-consumption resolution."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.projectile_sweeps import ProjectileCollision, sweep_projectiles
from kiwi.sim.projectiles import Projectile, ProjectileStore
from kiwi.sim.state import MissionState


@dataclass(frozen=True, slots=True)
class ProjectileImpact:
    """One collision that consumed a live projectile during the current tick."""

    tick: int
    projectile: Projectile
    collision: ProjectileCollision

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("projectile impact tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("projectile impact tick must fit non-negative signed 64-bit range")
        if not isinstance(self.projectile, Projectile):
            raise ValueError("projectile impact requires a projectile")
        if not isinstance(self.collision, ProjectileCollision):
            raise ValueError("projectile impact requires a projectile collision")
        if self.projectile.position.elevation != self.collision.position.elevation:
            raise ValueError("projectile impact collision must share projectile elevation")


@dataclass(frozen=True, slots=True)
class ProjectileImpactPhase:
    """One projectile advance successor and projectile-ID-ordered collisions."""

    state: MissionState
    impacts: tuple[ProjectileImpact, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("projectile impact phase requires mission state")
        if not isinstance(self.impacts, tuple):
            raise ValueError("projectile impact phase must use immutable impacts")
        remaining_ids = tuple(
            projectile.projectile_id for projectile in self.state.projectiles.entries
        )
        previous_projectile_id = 0
        for impact in self.impacts:
            if not isinstance(impact, ProjectileImpact):
                raise ValueError("projectile impact phase must contain projectile impacts")
            if impact.tick != self.state.tick:
                raise ValueError("projectile impacts must share the state tick")
            projectile_id = impact.projectile.projectile_id
            if projectile_id.value <= previous_projectile_id:
                raise ValueError("projectile impacts must be projectile-ID ordered")
            if projectile_id in remaining_ids:
                raise ValueError("impacted projectiles must be removed from successor state")
            previous_projectile_id = projectile_id.value


def advance_projectiles(state: MissionState) -> MissionState:
    """Advance live projectiles and return only the authoritative successor."""
    return resolve_projectile_impacts(state).state


def resolve_projectile_impacts(state: MissionState) -> ProjectileImpactPhase:
    """Consume collisions, advance survivors, and expire terminal-lifetime shots."""
    if not isinstance(state, MissionState):
        raise ValueError("projectile impact resolution requires mission state")
    sweeps = sweep_projectiles(state)
    survivors: list[Projectile] = []
    impacts: list[ProjectileImpact] = []
    for projectile, sweep in zip(state.projectiles.entries, sweeps, strict=True):
        if projectile.projectile_id != sweep.projectile_id:
            raise AssertionError("projectile sweep order must match projectile state")
        if sweep.collision is not None:
            impacts.append(ProjectileImpact(state.tick, projectile, sweep.collision))
            continue
        if projectile.remaining_ticks > 1:
            survivors.append(
                replace(
                    projectile,
                    position=sweep.end_position,
                    remaining_ticks=projectile.remaining_ticks - 1,
                )
            )
    return ProjectileImpactPhase(
        replace(state, projectiles=ProjectileStore(tuple(survivors))),
        tuple(impacts),
    )
