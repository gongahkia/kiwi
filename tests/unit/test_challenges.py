from __future__ import annotations

from datetime import date

from kiwi.content.challenges import (
    DISTRICT_TILE_COUNT,
    ChallengeMode,
    daily_challenge,
    generate_district,
    practice_challenge,
)


def test_daily_district_is_replay_regenerable_and_has_complete_material_grid() -> None:
    challenge = daily_challenge(date(2026, 8, 6))

    first = generate_district(challenge)
    second = generate_district(challenge)

    assert first == second
    assert first.challenge.mode is ChallengeMode.DAILY
    assert first.mission.mission_id == "glasshouse"
    assert len(first.tiles) == DISTRICT_TILE_COUNT**2
    assert first.layout_hash == second.layout_hash


def test_practice_contract_escalation_changes_seed_but_remains_deterministic() -> None:
    first = practice_challenge(42)
    second = first.next_contract()

    assert first.mode is ChallengeMode.PRACTICE
    assert second.contract_index == 1
    assert second.seed != first.seed
    assert generate_district(second) == generate_district(practice_challenge(42, 1))
