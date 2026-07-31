"""Canonical fixed-step progression of active movement actions."""

from __future__ import annotations

from dataclasses import replace
from typing import NamedTuple

from kiwi.domain.geometry import WorldPosition
from kiwi.sim.collision import movement_segment_collides_map, movement_segments_violate_separation
from kiwi.sim.state import (
    EntityState,
    MissionState,
    MovementAction,
    movement_action_position,
    movement_action_segment_length,
)

OPERATIVE_MOVE_SPEED_PER_TICK = 100


class _MovementAdvance(NamedTuple):
    entity_id: int
    successor: MovementAction | None
    start: WorldPosition
    goal: WorldPosition


def progress_movement_actions(state: MissionState) -> MissionState:
    """Advance every active action once in canonical entity-ID order."""
    if not isinstance(state, MissionState):
        raise ValueError("movement progression requires mission state")
    if not state.movement_actions:
        return state
    actions = state.movement_actions
    action_index = 0
    resolved: list[_MovementAdvance] = []
    entities: list[WorldPosition] = []
    next_actions: list[MovementAction] = []
    for entity_index, entity in enumerate(state.entities):
        action = actions[action_index] if action_index < len(actions) else None
        if action is None or action.entity_id != entity.entity_id:
            resolved.append(
                _MovementAdvance(entity.entity_id.value, None, entity.position, entity.position)
            )
            entities.append(entity.position)
            continue
        action_index += 1
        advance = _advance_action(action, entity.position)
        if _advance_is_blocked(advance, resolved, state.entities[entity_index + 1 :], state):
            advance = _MovementAdvance(
                action.entity_id.value, action, entity.position, entity.position
            )
        resolved.append(advance)
        entities.append(advance.goal)
        if advance.successor is not None:
            next_actions.append(advance.successor)
    return replace(
        state,
        entities=tuple(
            replace(entity, position=position)
            for entity, position in zip(state.entities, entities, strict=True)
        ),
        movement_actions=tuple(next_actions),
    )


def _advance_action(action: MovementAction, start: WorldPosition) -> _MovementAdvance:
    length = movement_action_segment_length(action)
    progressed = min(action.segment_progress + OPERATIVE_MOVE_SPEED_PER_TICK, length)
    if progressed < length:
        successor = replace(action, segment_progress=progressed)
        return _MovementAdvance(
            action.entity_id.value, successor, start, movement_action_position(successor)
        )
    target = action.path.waypoints[action.next_waypoint_index]
    if action.next_waypoint_index + 1 == len(action.path.waypoints):
        return _MovementAdvance(action.entity_id.value, None, start, target)
    return _MovementAdvance(
        action.entity_id.value,
        replace(action, next_waypoint_index=action.next_waypoint_index + 1, segment_progress=0),
        start,
        target,
    )


def _advance_is_blocked(
    advance: _MovementAdvance,
    resolved: list[_MovementAdvance],
    unprocessed: tuple[EntityState, ...],
    state: MissionState,
) -> bool:
    if state.map_geometry is None:
        raise AssertionError("movement actions require mission map geometry")
    if movement_segment_collides_map(advance.start, advance.goal, state.map_geometry):
        return True
    if any(
        movement_segments_violate_separation(
            advance.start,
            advance.goal,
            previous.start,
            previous.goal,
        )
        for previous in resolved
    ):
        return True
    return any(
        movement_segments_violate_separation(
            advance.start,
            advance.goal,
            entity.position,
            entity.position,
        )
        for entity in unprocessed
    )
