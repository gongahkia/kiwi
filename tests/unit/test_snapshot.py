from __future__ import annotations

from dataclasses import fields, replace

import pytest

from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.hashing import StateDecodeCode, hash_canonical_state
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.snapshot import (
    AuthoritySnapshot,
    SnapshotRestoreCode,
    SnapshotRestoreFailure,
    capture_authority_snapshot,
    restore_authority_snapshot,
)
from kiwi.sim.state import MissionPhase, MissionState


def test_authority_snapshot_restores_exact_state_and_hash() -> None:
    state = reduce_one_tick(MissionState(), FixedTickClock(TickRate.HZ_30)).state

    snapshot = capture_authority_snapshot(state)
    restored = restore_authority_snapshot(snapshot)

    assert restored == state
    assert snapshot.tick == state.tick
    assert snapshot.state_hash == hash_canonical_state(state)
    assert tuple(field.name for field in fields(AuthoritySnapshot)) == (
        "tick",
        "canonical_state",
        "state_hash",
    )


@pytest.mark.parametrize(
    ("snapshot", "code"),
    (
        (
            lambda snapshot: replace(snapshot, canonical_state=b""),
            SnapshotRestoreCode.INVALID_PAYLOAD,
        ),
        (
            lambda snapshot: replace(snapshot, tick=snapshot.tick + 1),
            SnapshotRestoreCode.TICK_MISMATCH,
        ),
        (
            lambda snapshot: replace(
                snapshot,
                state_hash=hash_canonical_state(replace(MissionState(), phase=MissionPhase.ACTIVE)),
            ),
            SnapshotRestoreCode.HASH_MISMATCH,
        ),
    ),
)
def test_authority_snapshot_restore_reports_structured_failures(
    snapshot: object, code: SnapshotRestoreCode
) -> None:
    captured = capture_authority_snapshot(MissionState())
    invalid_snapshot = snapshot(captured)  # type: ignore[operator]

    restored = restore_authority_snapshot(invalid_snapshot)

    assert isinstance(restored, SnapshotRestoreFailure)
    assert restored.code is code
    if code is SnapshotRestoreCode.INVALID_PAYLOAD:
        assert restored.state_failure is not None
        assert restored.state_failure.code is StateDecodeCode.INVALID_MAGIC


def test_authority_snapshot_restore_requires_snapshot_value() -> None:
    with pytest.raises(TypeError, match="AuthoritySnapshot"):
        restore_authority_snapshot(object())  # type: ignore[arg-type]
