from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EntityId, IdAllocator, WeaponId
from kiwi.sim.hashing import decode_canonical_state, encode_canonical_state, hash_canonical_state
from kiwi.sim.state import MissionState, add_entity
from kiwi.sim.weapons import AimState, AimStore, Ammunition, EquippedWeapon, WeaponStore


def test_weapon_and_aim_stores_are_canonical_and_use_implicit_zero_aim() -> None:
    first = EquippedWeapon(WeaponId(1), EntityId(1), Ammunition(30, 30))
    second = EquippedWeapon(WeaponId(2), EntityId(1), Ammunition(5, 0))
    weapons = WeaponStore((first, second))
    aim = AimStore((AimState(EntityId(1), 4_000),))

    assert weapons.weapon_for(WeaponId(2)) == second
    assert weapons.weapon_for(WeaponId(3)) is None
    assert aim.quality_for(EntityId(1)) == 4_000
    assert aim.quality_for(EntityId(2)) == 0
    with pytest.raises(ValueError, match="weapon-ID ordered"):
        WeaponStore((second, first))
    with pytest.raises(ValueError, match="entity-ID ordered"):
        AimStore((AimState(EntityId(2), 1), AimState(EntityId(1), 1)))


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: Ammunition(0, 0), "configured range"),
        (lambda: Ammunition(3, 4), "between zero"),
        (lambda: AimState(EntityId(1), 0), "between one"),
        (lambda: EquippedWeapon(EntityId(1), EntityId(1), Ammunition(1, 1)), "weapon ID"),  # type: ignore[arg-type]
    ),
)
def test_weapon_values_reject_invalid_inputs(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def test_weapon_and_aim_authority_state_round_trips_and_hashes() -> None:
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(0), WorldSubunits(0)))
    weapon_id, allocator = state.id_allocator.allocate_weapon()
    equipped = EquippedWeapon(weapon_id, entity.entity_id, Ammunition(30, 12))
    state = replace(
        state,
        id_allocator=allocator,
        weapons=WeaponStore((equipped,)),
        aim_states=AimStore((AimState(entity.entity_id, 2_500),)),
    )

    encoded = encode_canonical_state(state)
    decoded = decode_canonical_state(encoded)

    assert decoded == state
    assert hash_canonical_state(state) != hash_canonical_state(
        replace(state, weapons=WeaponStore(), aim_states=AimStore())
    )
    assert encoded


def test_mission_state_rejects_orphan_or_unallocated_weapon_and_aim_values() -> None:
    weapon = EquippedWeapon(WeaponId(1), EntityId(1), Ammunition(1, 1))

    with pytest.raises(ValueError, match="weapon IDs must be allocated"):
        MissionState(weapons=WeaponStore((weapon,)))
    weapon_id, allocator = IdAllocator().allocate_weapon()
    with pytest.raises(ValueError, match="weapons must belong"):
        MissionState(
            weapons=WeaponStore((replace(weapon, weapon_id=weapon_id),)), id_allocator=allocator
        )
    with pytest.raises(ValueError, match="aim states must belong"):
        MissionState(aim_states=AimStore((AimState(EntityId(1), 1),)))
