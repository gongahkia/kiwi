from __future__ import annotations

from dataclasses import replace

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import CoverId, EntityId, IdAllocator, IntentionId, PolicyInvocationId
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.sim.arbitration import (
    ArbitrationStatus,
    IntentionArbitration,
    IntentionCandidate,
    PolicyArbitrationPhase,
)
from kiwi.sim.cover_intentions import (
    TakeCoverRejectionReason,
    resolve_selected_take_cover,
)
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)
from kiwi.sim.intentions import IntentionKind, IntentionOrigin, TakeCoverIntention
from kiwi.sim.state import MissionState, add_entity


def test_take_cover_reserves_first_available_same_side_slot_in_entity_order() -> None:
    state, candidates = _state_and_candidates((CoverSide.LEFT, CoverSide.LEFT))

    phase = resolve_selected_take_cover(state, _arbitration(state, candidates))

    assert tuple(resolution.slot_index for resolution in phase.resolutions) == (0, 1)
    assert all(resolution.reason is None for resolution in phase.resolutions)
    assert tuple(
        (reservation.slot_index, reservation.entity_id, reservation.intention_id)
        for reservation in phase.state.cover_reservations.entries
    ) == (
        (0, candidates[0].origin.issuer_entity_id, IntentionId(1)),
        (1, candidates[1].origin.issuer_entity_id, IntentionId(2)),
    )


def test_take_cover_reports_same_batch_contention_with_the_winning_intention() -> None:
    state, candidates = _state_and_candidates((CoverSide.LEFT,))

    phase = resolve_selected_take_cover(state, _arbitration(state, candidates))

    assert phase.resolutions[0].reason is None
    assert phase.resolutions[1].reason is TakeCoverRejectionReason.SLOT_CONTESTED
    assert phase.resolutions[1].competing_intention_id == IntentionId(1)
    assert (
        phase.state.cover_reservations.entries[0].entity_id == candidates[0].origin.issuer_entity_id
    )


def test_take_cover_reports_missing_cover_without_mutating_reservations() -> None:
    state, candidates = _state_and_candidates((CoverSide.LEFT,))
    missing = replace(
        candidates[0],
        intention=TakeCoverIntention(CoverId(2), CoverSide.LEFT),
    )
    arbitration = _arbitration(state, (missing,))

    phase = resolve_selected_take_cover(state, arbitration)

    assert phase.state.cover_reservations.entries == ()
    assert phase.resolutions[0].reason is TakeCoverRejectionReason.COVER_NOT_FOUND


def test_take_cover_reports_unavailable_requested_side_without_mutating_reservations() -> None:
    state, candidates = _state_and_candidates((CoverSide.LEFT,))
    unavailable = replace(
        candidates[0],
        intention=TakeCoverIntention(CoverId(1), CoverSide.RIGHT),
    )

    phase = resolve_selected_take_cover(state, _arbitration(state, (unavailable,)))

    assert phase.state.cover_reservations.entries == ()
    assert phase.resolutions[0].reason is TakeCoverRejectionReason.SIDE_UNAVAILABLE


def _state_and_candidates(
    sides: tuple[CoverSide, ...],
) -> tuple[MissionState, tuple[IntentionCandidate, IntentionCandidate]]:
    cover_id, allocator = IdAllocator().allocate_cover()
    slots = tuple(
        CoverSlot(
            index,
            WorldPosition(WorldSubunits(index * 1_000), WorldSubunits(-350)),
            side,
        )
        for index, side in enumerate(sides)
    )
    cover = CoverSegment(
        cover_id,
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
        WorldPosition(WorldSubunits(2_000), WorldSubunits(0)),
        CoverHeight.HIGH,
        CoverIntegrity(10_000),
        slots,
    )
    state, first = add_entity(
        MissionState(covers=CoverStore((cover,)), id_allocator=allocator),
        WorldPosition(WorldSubunits(-1_000), WorldSubunits(0)),
    )
    state, second = add_entity(state, WorldPosition(WorldSubunits(-2_000), WorldSubunits(0)))
    first_intention_id, allocator = state.id_allocator.allocate_intention()
    second_intention_id, allocator = allocator.allocate_intention()
    state = replace(state, id_allocator=allocator)
    source = SourceFile(SourceFileId("take-cover.dtr"), "TakeCover")
    return state, (
        _candidate(first.entity_id, first_intention_id, source),
        _candidate(second.entity_id, second_intention_id, source),
    )


def _candidate(
    entity_id: EntityId,
    intention_id: IntentionId,
    source: SourceFile,
) -> IntentionCandidate:
    return IntentionCandidate(
        IntentionOrigin(
            intention_id,
            entity_id,
            PolicyInvocationId(intention_id.value),
            ExpressionId(intention_id.value),
            source.span(ByteOffset(0), ByteOffset(9)),
            0,
            0,
            IntentionKind.TAKE_COVER,
        ),
        TakeCoverIntention(CoverId(1), CoverSide.LEFT),
    )


def _arbitration(
    state: MissionState,
    candidates: tuple[IntentionCandidate, ...],
) -> PolicyArbitrationPhase:
    return PolicyArbitrationPhase(
        state,
        tuple(
            IntentionArbitration(candidate, ArbitrationStatus.SELECTED) for candidate in candidates
        ),
    )
