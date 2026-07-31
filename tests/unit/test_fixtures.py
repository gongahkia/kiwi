from __future__ import annotations

from pathlib import Path

import pytest

from kiwi.content.fixtures import (
    FixtureDiagnosticCode,
    FixtureLoadFailure,
    KernelFixture,
    load_kernel_fixture_bytes,
    load_kernel_fixture_file,
)
from kiwi.sim.bootstrap import build_initial_state
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.determinism import run_determinism_harness
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.randomness import MissionSeed
from kiwi.sim.state import MissionState

FIXTURE_PATH = Path(__file__).resolve().parents[1] / "fixtures" / "minimal.kfixture.json"


def _initial_state(fixture: KernelFixture) -> MissionState:
    return build_initial_state(
        MissionSeed(fixture.seed),
        tuple(entity.position for entity in fixture.entities),
        fixture.scheduled_trigger_ticks,
    )


def test_kernel_fixture_loads_canonical_inputs_and_runs_headlessly() -> None:
    fixture = load_kernel_fixture_file(FIXTURE_PATH)

    assert isinstance(fixture, KernelFixture)
    assert tuple(entity.content_id for entity in fixture.entities) == ("alpha", "bravo")
    assert fixture.scheduled_trigger_ticks == (1, 2)
    report = run_determinism_harness(
        _initial_state(fixture),
        FixedTickClock(TickRate(fixture.tick_rate)),
        3,
    )
    assert report.matches


def test_fixture_entity_mapping_order_does_not_change_the_initial_state_hash() -> None:
    common = (
        b'"format":"kiwi-kernel-fixture","version":1,"id":"order",'
        b'"tick_rate":30,"seed":4,"scheduled_triggers":[2]'
    )
    alpha_then_bravo = b"{" + common + b',"entities":{"alpha":{"x":0,"y":1},"bravo":{"x":2,"y":3}}}'
    bravo_then_alpha = b"{" + common + b',"entities":{"bravo":{"x":2,"y":3},"alpha":{"x":0,"y":1}}}'
    first = load_kernel_fixture_bytes(alpha_then_bravo)
    second = load_kernel_fixture_bytes(bravo_then_alpha)

    assert isinstance(first, KernelFixture)
    assert isinstance(second, KernelFixture)
    assert first == second
    assert hash_canonical_state(_initial_state(first)) == hash_canonical_state(
        _initial_state(second)
    )


@pytest.mark.parametrize(
    ("data", "code", "path"),
    (
        (b"\xff", FixtureDiagnosticCode.INVALID_UTF8, "$"),
        (b"{", FixtureDiagnosticCode.INVALID_JSON, "$"),
        (
            b'{"format":"kiwi-kernel-fixture","version":1,"id":"bad","tick_rate":30,"seed":0,"entities":{},"scheduled_triggers":[],"extra":0}',
            FixtureDiagnosticCode.UNKNOWN_FIELD,
            "$",
        ),
        (
            b'{"format":"kiwi-kernel-fixture","version":1,"id":"bad","tick_rate":30,"seed":0,"entities":{"alpha":{"x":0,"y":0,"elevation":-1}},"scheduled_triggers":[]}',
            FixtureDiagnosticCode.INVALID_VALUE,
            "$.entities.alpha.elevation",
        ),
    ),
)
def test_kernel_fixture_loader_returns_structured_failures(
    data: bytes, code: FixtureDiagnosticCode, path: str
) -> None:
    result = load_kernel_fixture_bytes(data, "fixture.json")

    assert isinstance(result, FixtureLoadFailure)
    assert result.source == "fixture.json"
    assert result.diagnostics[0].code is code
    assert result.diagnostics[0].path == path


def test_kernel_fixture_loader_rejects_duplicate_json_fields() -> None:
    result = load_kernel_fixture_bytes(
        b'{"format":"kiwi-kernel-fixture","format":"kiwi-kernel-fixture"}'
    )

    assert isinstance(result, FixtureLoadFailure)
    assert result.diagnostics[0].code is FixtureDiagnosticCode.DUPLICATE_FIELD
