"""Deterministic target-free aim progression after movement resolution."""

from __future__ import annotations

from dataclasses import dataclass, replace

from kiwi.domain.ids import EntityId
from kiwi.sim.clock import FixedTickClock
from kiwi.sim.movement import MovementResolution
from kiwi.sim.state import MissionState
from kiwi.sim.weapons import MAX_AIM_QUALITY_BASIS_POINTS


@dataclass(frozen=True, slots=True)
class AimProgression:
    """One entity's exact aim update and its modifier breakdown."""

    entity_id: EntityId
    quality_before: int
    suppression_basis_points: int
    quality_ceiling: int
    base_gain: int
    moved: bool
    quality_after: int

    def __post_init__(self) -> None:
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("aim progression requires an entity ID")
        values = (
            self.quality_before,
            self.suppression_basis_points,
            self.quality_ceiling,
            self.base_gain,
            self.quality_after,
        )
        if any(not isinstance(value, int) or isinstance(value, bool) for value in values):
            raise ValueError("aim progression values must be integers")
        if not 0 <= self.quality_before <= MAX_AIM_QUALITY_BASIS_POINTS:
            raise ValueError("aim progression previous quality is outside the configured range")
        if not 0 <= self.suppression_basis_points <= MAX_AIM_QUALITY_BASIS_POINTS:
            raise ValueError("aim progression suppression is outside the configured range")
        if self.quality_ceiling != MAX_AIM_QUALITY_BASIS_POINTS - self.suppression_basis_points:
            raise ValueError("aim progression ceiling must match suppression")
        if self.base_gain < 0:
            raise ValueError("aim progression gain must be non-negative")
        if not isinstance(self.moved, bool):
            raise ValueError("aim progression movement flag must be boolean")
        expected_quality = (
            0
            if self.moved
            else min(self.quality_ceiling, self.quality_before + self.base_gain)
        )
        if self.quality_after != expected_quality:
            raise ValueError("aim progression result does not match its modifiers")


@dataclass(frozen=True, slots=True)
class AimProgressionPhase:
    """One aim phase successor and entity-ID-ordered exact results."""

    state: MissionState
    progressions: tuple[AimProgression, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("aim progression phase requires mission state")
        if not isinstance(self.progressions, tuple):
            raise ValueError("aim progression results must be an immutable tuple")
        previous_entity_id = 0
        for progression in self.progressions:
            if not isinstance(progression, AimProgression):
                raise ValueError("aim progression results must be aim progressions")
            if progression.entity_id.value <= previous_entity_id:
                raise ValueError("aim progression results must be entity-ID ordered")
            previous_entity_id = progression.entity_id.value


def progress_aim_states(
    state: MissionState,
    clock: FixedTickClock,
    movement_resolutions: tuple[MovementResolution, ...],
) -> MissionState:
    """Advance target-free aim and return only the authority successor."""
    return resolve_aim_progression(state, clock, movement_resolutions).state


def resolve_aim_progression(
    state: MissionState,
    clock: FixedTickClock,
    movement_resolutions: tuple[MovementResolution, ...],
) -> AimProgressionPhase:
    """Apply one real-time-normalized aim update after movement resolution."""
    if not isinstance(state, MissionState):
        raise ValueError("aim progression requires mission state")
    if not isinstance(clock, FixedTickClock):
        raise ValueError("aim progression requires a fixed tick clock")
    if not isinstance(movement_resolutions, tuple):
        raise ValueError("aim progression requires immutable movement resolutions")
    entity_ids = tuple(entity.entity_id for entity in state.entities)
    moving_entity_ids: set[EntityId] = set()
    previous_entity_id = 0
    for resolution in movement_resolutions:
        if not isinstance(resolution, MovementResolution):
            raise ValueError("aim progression requires movement resolutions")
        if resolution.tick != state.tick:
            raise ValueError("aim progression resolutions must match the mission tick")
        if resolution.entity_id.value <= previous_entity_id:
            raise ValueError("aim progression resolutions must be entity-ID ordered")
        if resolution.entity_id not in entity_ids:
            raise ValueError("aim progression resolutions must belong to mission entities")
        if resolution.result_position != resolution.start_position:
            moving_entity_ids.add(resolution.entity_id)
        previous_entity_id = resolution.entity_id.value
    base_gain = _aim_gain_for_tick(state.tick, int(clock.rate))
    aim_states = state.aim_states
    progressions: list[AimProgression] = []
    for entity in state.entities:
        entity_id = entity.entity_id
        quality_before = aim_states.quality_for(entity_id)
        suppression = state.suppressions.suppression_for(entity_id)
        ceiling = MAX_AIM_QUALITY_BASIS_POINTS - suppression
        moved = entity_id in moving_entity_ids
        progression = AimProgression(
            entity_id,
            quality_before,
            suppression,
            ceiling,
            0 if moved else base_gain,
            moved,
            0 if moved else min(ceiling, quality_before + base_gain),
        )
        aim_states = aim_states.with_quality(entity_id, progression.quality_after)
        progressions.append(progression)
    return AimProgressionPhase(replace(state, aim_states=aim_states), tuple(progressions))


def _aim_gain_for_tick(tick: int, tick_rate: int) -> int:
    return (
        (tick + 1) * MAX_AIM_QUALITY_BASIS_POINTS // tick_rate
        - tick * MAX_AIM_QUALITY_BASIS_POINTS // tick_rate
    )
