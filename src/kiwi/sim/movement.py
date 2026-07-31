"""Canonical fixed-step progression of active movement actions."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.domain.geometry import WorldPosition
from kiwi.domain.ids import EntityId, EventId
from kiwi.sim.collision import movement_segment_collides_map, movement_segments_violate_separation
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.state import (
    EntityState,
    MissionState,
    MovementAction,
    movement_action_position,
    movement_action_segment_length,
)

OPERATIVE_MOVE_SPEED_PER_TICK = 100


class MovementResolutionKind(StrEnum):
    """The closed outcome of one entity's movement attempt."""

    PROGRESSED = "progressed"
    BLOCKED = "blocked"
    ARRIVED = "arrived"


class MovementBlockReason(StrEnum):
    """Stable reasons an attempted movement segment cannot be accepted."""

    MAP_COLLISION = "map_collision"
    OPERATIVE_SEPARATION = "operative_separation"


@dataclass(frozen=True, slots=True)
class MovementResolution:
    """One exact movement attempt and its accepted or held result."""

    tick: int
    entity_id: EntityId
    start_position: WorldPosition
    attempted_position: WorldPosition
    result_position: WorldPosition
    kind: MovementResolutionKind
    block_reason: MovementBlockReason | None = None
    origin_event_id: EventId | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("movement resolution tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("movement resolution tick must fit non-negative signed 64-bit range")
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("movement resolution requires an entity ID")
        positions = (self.start_position, self.attempted_position, self.result_position)
        if any(not isinstance(position, WorldPosition) for position in positions):
            raise ValueError("movement resolution positions must be world positions")
        if any(position.elevation != self.start_position.elevation for position in positions):
            raise ValueError("movement resolution positions must share an elevation layer")
        if not isinstance(self.kind, MovementResolutionKind):
            raise ValueError("movement resolution requires a resolution kind")
        if self.origin_event_id is not None and not isinstance(self.origin_event_id, EventId):
            raise ValueError("movement resolution origin event must be an event ID or absent")
        if self.kind is MovementResolutionKind.BLOCKED:
            if not isinstance(self.block_reason, MovementBlockReason):
                raise ValueError("blocked movement resolutions require a block reason")
            if self.result_position != self.start_position:
                raise ValueError("blocked movement resolutions must retain the start position")
            return
        if self.block_reason is not None:
            raise ValueError("successful movement resolutions cannot carry a block reason")
        if self.result_position != self.attempted_position:
            raise ValueError("successful movement resolutions must accept the attempted position")


@dataclass(frozen=True, slots=True)
class MovementPhase:
    """One tick's successor state and entity-ID-ordered movement outcomes."""

    state: MissionState
    resolutions: tuple[MovementResolution, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("movement phase requires mission state")
        if not isinstance(self.resolutions, tuple):
            raise ValueError("movement phase resolutions must be an immutable tuple")
        previous_entity_id = 0
        for resolution in self.resolutions:
            if not isinstance(resolution, MovementResolution):
                raise ValueError("movement phase resolutions must be movement resolutions")
            if resolution.tick != self.state.tick:
                raise ValueError("movement phase resolutions must share the state tick")
            if resolution.entity_id.value <= previous_entity_id:
                raise ValueError("movement phase resolutions must be entity-ID ordered")
            previous_entity_id = resolution.entity_id.value


@dataclass(frozen=True, slots=True)
class _MovementAdvance:
    entity_id: int
    successor: MovementAction | None
    start: WorldPosition
    attempted: WorldPosition
    result: WorldPosition


def progress_movement_actions(state: MissionState) -> MissionState:
    """Advance every active action once in canonical entity-ID order."""
    return resolve_movement_actions(state).state


def resolve_movement_actions(state: MissionState) -> MovementPhase:
    """Resolve movement attempts with exact collision and separation outcomes."""
    if not isinstance(state, MissionState):
        raise ValueError("movement progression requires mission state")
    if not state.movement_actions:
        return MovementPhase(state, ())
    actions = state.movement_actions
    action_index = 0
    resolved: list[_MovementAdvance] = []
    entities: list[WorldPosition] = []
    next_actions: list[MovementAction] = []
    resolutions: list[MovementResolution] = []
    for entity_index, entity in enumerate(state.entities):
        action = actions[action_index] if action_index < len(actions) else None
        if action is None or action.entity_id != entity.entity_id:
            resolved.append(
                _MovementAdvance(
                    entity.entity_id.value,
                    None,
                    entity.position,
                    entity.position,
                    entity.position,
                )
            )
            entities.append(entity.position)
            continue
        action_index += 1
        advance = _advance_action(action, entity.position)
        block_reason = _block_reason(advance, resolved, state.entities[entity_index + 1 :], state)
        if block_reason is not None:
            advance = replace(
                advance,
                successor=action,
                result=entity.position,
            )
        resolved.append(advance)
        entities.append(advance.result)
        if advance.successor is not None:
            next_actions.append(advance.successor)
        resolutions.append(
            MovementResolution(
                state.tick,
                entity.entity_id,
                advance.start,
                advance.attempted,
                advance.result,
                (
                    MovementResolutionKind.BLOCKED
                    if block_reason is not None
                    else (
                        MovementResolutionKind.ARRIVED
                        if advance.successor is None
                        else MovementResolutionKind.PROGRESSED
                    )
                ),
                block_reason,
                action.origin_event_id,
            )
        )
    next_state = replace(
        state,
        entities=tuple(
            replace(entity, position=position)
            for entity, position in zip(state.entities, entities, strict=True)
        ),
        movement_actions=tuple(next_actions),
    )
    return MovementPhase(next_state, tuple(resolutions))


def _advance_action(action: MovementAction, start: WorldPosition) -> _MovementAdvance:
    length = movement_action_segment_length(action)
    progressed = min(action.segment_progress + OPERATIVE_MOVE_SPEED_PER_TICK, length)
    if progressed < length:
        successor = replace(action, segment_progress=progressed)
        position = movement_action_position(successor)
        return _MovementAdvance(
            action.entity_id.value,
            successor,
            start,
            position,
            position,
        )
    target = action.path.waypoints[action.next_waypoint_index]
    if action.next_waypoint_index + 1 == len(action.path.waypoints):
        return _MovementAdvance(action.entity_id.value, None, start, target, target)
    return _MovementAdvance(
        action.entity_id.value,
        replace(action, next_waypoint_index=action.next_waypoint_index + 1, segment_progress=0),
        start,
        target,
        target,
    )


def _block_reason(
    advance: _MovementAdvance,
    resolved: list[_MovementAdvance],
    unprocessed: tuple[EntityState, ...],
    state: MissionState,
) -> MovementBlockReason | None:
    if state.map_geometry is None:
        raise AssertionError("movement actions require mission map geometry")
    if movement_segment_collides_map(advance.start, advance.attempted, state.map_geometry):
        return MovementBlockReason.MAP_COLLISION
    if any(
        movement_segments_violate_separation(
            advance.start,
            advance.attempted,
            previous.start,
            previous.result,
        )
        for previous in resolved
    ):
        return MovementBlockReason.OPERATIVE_SEPARATION
    if any(
        movement_segments_violate_separation(
            advance.start,
            advance.attempted,
            entity.position,
            entity.position,
        )
        for entity in unprocessed
    ):
        return MovementBlockReason.OPERATIVE_SEPARATION
    return None
