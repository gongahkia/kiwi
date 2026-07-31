from __future__ import annotations

import pytest

from kiwi.domain.ids import MAX_STABLE_ID
from kiwi.sim.randomness import (
    MissionSeed,
    RandomDraw,
    RandomPurpose,
    RandomStreamId,
    RandomStreams,
    RandomStreamState,
    default_random_streams,
    draw_uint32,
)


def test_named_streams_are_independent_and_preserve_prior_state() -> None:
    initial = RandomStreams.from_seed(MissionSeed(7))
    weapon_result, weapon_draw, after_weapon = draw_uint32(
        initial,
        RandomStreamId.WEAPON_DISPERSION,
        RandomPurpose("weapon_dispersion"),
    )
    damage_result, damage_draw, after_damage = draw_uint32(
        after_weapon,
        RandomStreamId.DAMAGE_VARIATION,
        RandomPurpose("damage_variation"),
    )

    assert initial.stream_state(RandomStreamId.WEAPON_DISPERSION).next_draw_index == 0
    assert weapon_draw.draw_index == 0
    assert damage_draw.draw_index == 0
    assert after_weapon.stream_state(RandomStreamId.DAMAGE_VARIATION) == initial.stream_state(
        RandomStreamId.DAMAGE_VARIATION
    )
    assert after_damage.stream_state(RandomStreamId.WEAPON_DISPERSION) == after_weapon.stream_state(
        RandomStreamId.WEAPON_DISPERSION
    )
    assert 0 <= weapon_result <= (1 << 32) - 1
    assert 0 <= damage_result <= (1 << 32) - 1


def test_same_seed_and_draw_sequence_produce_identical_draw_records() -> None:
    purpose = RandomPurpose("scenario_spawn")
    first = RandomStreams.from_seed(MissionSeed(99))
    second = RandomStreams.from_seed(MissionSeed(99))

    first_result, first_draw, first_after = draw_uint32(
        first, RandomStreamId.SCENARIO_SPAWN, purpose
    )
    second_result, second_draw, second_after = draw_uint32(
        second, RandomStreamId.SCENARIO_SPAWN, purpose
    )

    assert (first_result, first_draw, first_after) == (second_result, second_draw, second_after)
    assert default_random_streams() == RandomStreams.from_seed(MissionSeed(0))


def test_random_algorithm_version_one_has_a_stable_zero_seed_vector() -> None:
    streams = RandomStreams.from_seed(MissionSeed(0))
    purpose = RandomPurpose("scenario_spawn")
    values: list[tuple[int, int]] = []

    for _ in range(3):
        result, draw, streams = draw_uint32(streams, RandomStreamId.SCENARIO_SPAWN, purpose)
        values.append((result, draw.draw_index))

    assert values == [(2_975_939_976, 0), (1_012_613_902, 1), (3_822_070_894, 2)]


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: MissionSeed(-1), "unsigned"),
        (lambda: MissionSeed(1 << 64), "unsigned"),
        (lambda: RandomPurpose("Scenario"), "lowercase"),
        (lambda: RandomStreamState(1 << 64), "unsigned"),
        (lambda: RandomStreamState(0, MAX_STABLE_ID + 2), "signed 64-bit"),
        (lambda: RandomStreams(MissionSeed(0), []), "immutable state tuple"),  # type: ignore[arg-type]
        (lambda: RandomStreams.from_seed(object()), "mission seed"),  # type: ignore[arg-type]
        (
            lambda: RandomDraw(
                RandomStreamId.ENEMY_POLICY,
                0,
                1,
                (1 << 32) - 1,
                1,
                RandomPurpose("enemy_policy"),
            ),
            "unsigned 32-bit",
        ),
    ),
)
def test_randomness_rejects_invalid_canonical_values(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
