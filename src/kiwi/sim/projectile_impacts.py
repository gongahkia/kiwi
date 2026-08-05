"""Canonical projectile advancement and collision-consumption resolution."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.sim.intentions import IntentionOrigin
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

    @property
    def source_intention(self) -> IntentionOrigin:
        """Return the full Fire origin retained by the impacted projectile."""
        return self.projectile.source_intention


class ProjectileResolutionKind(StrEnum):
    """The closed physical outcome of one live projectile in one tick."""

    ADVANCED = "advanced"
    EXPIRED = "expired"
    IMPACTED = "impacted"


@dataclass(frozen=True, slots=True)
class ProjectileResolution:
    """One source projectile and its exact advancement, expiry, or impact result."""

    tick: int
    projectile: Projectile
    kind: ProjectileResolutionKind
    successor: Projectile | None = None
    impact: ProjectileImpact | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("projectile resolution tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("projectile resolution tick must fit non-negative signed 64-bit range")
        if not isinstance(self.projectile, Projectile):
            raise ValueError("projectile resolution requires a source projectile")
        if not isinstance(self.kind, ProjectileResolutionKind):
            raise ValueError("projectile resolution requires an outcome kind")
        if self.kind is ProjectileResolutionKind.ADVANCED:
            if not isinstance(self.successor, Projectile) or self.impact is not None:
                raise ValueError("advanced projectile resolutions require only a successor")
            if (
                self.successor.projectile_id != self.projectile.projectile_id
                or self.successor.owner_entity_id != self.projectile.owner_entity_id
                or self.successor.source_intention_id != self.projectile.source_intention_id
                or self.successor.velocity != self.projectile.velocity
                or self.successor.remaining_ticks != self.projectile.remaining_ticks - 1
            ):
                raise ValueError(
                    "advanced projectile successor must preserve its canonical identity"
                )
            return
        if self.kind is ProjectileResolutionKind.EXPIRED:
            if self.successor is not None or self.impact is not None:
                raise ValueError("expired projectile resolutions retain no successor or impact")
            if self.projectile.remaining_ticks != 1:
                raise ValueError("only terminal-lifetime projectiles can expire")
            return
        if self.successor is not None or not isinstance(self.impact, ProjectileImpact):
            raise ValueError("impacted projectile resolutions require only an impact")
        if self.impact.tick != self.tick or self.impact.projectile != self.projectile:
            raise ValueError("impacted projectile resolution must retain its exact impact")


@dataclass(frozen=True, slots=True)
class ProjectileImpactPhase:
    """One projectile advance successor and projectile-ID-ordered collisions."""

    state: MissionState
    impacts: tuple[ProjectileImpact, ...]
    resolutions: tuple[ProjectileResolution, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("projectile impact phase requires mission state")
        if not isinstance(self.impacts, tuple):
            raise ValueError("projectile impact phase must use immutable impacts")
        if not isinstance(self.resolutions, tuple):
            raise ValueError("projectile impact phase must use immutable resolutions")
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
        previous_projectile_id = 0
        successors: list[Projectile] = []
        expected_impacts: list[ProjectileImpact] = []
        for resolution in self.resolutions:
            if not isinstance(resolution, ProjectileResolution):
                raise ValueError("projectile impact phase must contain projectile resolutions")
            if resolution.tick != self.state.tick:
                raise ValueError("projectile resolutions must share the state tick")
            projectile_id = resolution.projectile.projectile_id
            if projectile_id.value <= previous_projectile_id:
                raise ValueError("projectile resolutions must be projectile-ID ordered")
            previous_projectile_id = projectile_id.value
            if resolution.successor is not None:
                successors.append(resolution.successor)
            if resolution.impact is not None:
                expected_impacts.append(resolution.impact)
        if self.resolutions and tuple(expected_impacts) != self.impacts:
            raise ValueError("projectile impact phase impacts must match projectile resolutions")
        if self.resolutions and tuple(successors) != self.state.projectiles.entries:
            raise ValueError("projectile impact phase state must retain projectile successors")


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
    resolutions: list[ProjectileResolution] = []
    for projectile, sweep in zip(state.projectiles.entries, sweeps, strict=True):
        if projectile.projectile_id != sweep.projectile_id:
            raise AssertionError("projectile sweep order must match projectile state")
        if sweep.collision is not None:
            impact = ProjectileImpact(state.tick, projectile, sweep.collision)
            impacts.append(impact)
            resolutions.append(
                ProjectileResolution(
                    state.tick,
                    projectile,
                    ProjectileResolutionKind.IMPACTED,
                    impact=impact,
                )
            )
            continue
        if projectile.remaining_ticks > 1:
            successor = replace(
                projectile,
                position=sweep.end_position,
                remaining_ticks=projectile.remaining_ticks - 1,
            )
            survivors.append(successor)
            resolutions.append(
                ProjectileResolution(
                    state.tick,
                    projectile,
                    ProjectileResolutionKind.ADVANCED,
                    successor,
                )
            )
            continue
        resolutions.append(
            ProjectileResolution(
                state.tick,
                projectile,
                ProjectileResolutionKind.EXPIRED,
            )
        )
    return ProjectileImpactPhase(
        replace(state, projectiles=ProjectileStore(tuple(survivors))),
        tuple(impacts),
        tuple(resolutions),
    )
