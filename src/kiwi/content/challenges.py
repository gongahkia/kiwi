"""Pure seeded Terminal challenge definitions and modular district generation."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from hashlib import blake2b

from kiwi.content.missions import (
    MissionCover,
    MissionCoverHeight,
    MissionCoverSide,
    MissionCoverSlot,
    MissionData,
    MissionObstacle,
    MissionRegion,
)
from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle, WorldSubunits

DISTRICT_GENERATOR_VERSION = 1
DISTRICT_TILE_COUNT = 32
DISTRICT_TILE_MILLIMETRES = 1_000
_DISTRICT_HALF_WIDTH = DISTRICT_TILE_COUNT * DISTRICT_TILE_MILLIMETRES // 2
_MAX_UINT64 = (1 << 64) - 1


class ChallengeMode(StrEnum):
    """The application-selected, replay-recorded challenge entry modes."""

    DAILY = "daily"
    PRACTICE = "practice"


class DistrictMaterial(StrEnum):
    """Renderer-facing terrain material tags copied from generated content."""

    FLOOR = "floor"
    LANE = "lane"
    COVER = "cover"
    WALL = "wall"


@dataclass(frozen=True, slots=True)
class ChallengeDefinition:
    """All authority inputs needed to regenerate one specific contract."""

    mode: ChallengeMode
    challenge_id: str
    seed: int
    generator_version: int = DISTRICT_GENERATOR_VERSION
    contract_index: int = 0

    def __post_init__(self) -> None:
        if not isinstance(self.mode, ChallengeMode):
            raise TypeError("challenge mode is invalid")
        if not _is_identifier(self.challenge_id):
            raise ValueError("challenge ID must be lowercase ASCII text")
        if (
            not isinstance(self.seed, int)
            or isinstance(self.seed, bool)
            or not 0 <= self.seed <= _MAX_UINT64
        ):
            raise ValueError("challenge seed must fit unsigned 64-bit range")
        if (
            not isinstance(self.generator_version, int)
            or isinstance(self.generator_version, bool)
            or self.generator_version != DISTRICT_GENERATOR_VERSION
        ):
            raise ValueError("challenge generator version is unsupported")
        if (
            not isinstance(self.contract_index, int)
            or isinstance(self.contract_index, bool)
            or self.contract_index < 0
        ):
            raise ValueError("challenge contract index must be non-negative")

    def next_contract(self) -> ChallengeDefinition:
        """Return the deterministic next escalation contract without reading a clock."""
        return ChallengeDefinition(
            self.mode,
            self.challenge_id,
            _derive_seed(self.seed, self.contract_index + 1),
            self.generator_version,
            self.contract_index + 1,
        )


@dataclass(frozen=True, slots=True)
class DistrictTile:
    """One stable map-grid cell for renderer material selection and inspection."""

    x: int
    y: int
    material: DistrictMaterial

    def __post_init__(self) -> None:
        if any(not isinstance(value, int) or isinstance(value, bool) for value in (self.x, self.y)):
            raise TypeError("district tile coordinates must be integers")
        if not 0 <= self.x < DISTRICT_TILE_COUNT or not 0 <= self.y < DISTRICT_TILE_COUNT:
            raise ValueError("district tile coordinates must fit the modular district")
        if not isinstance(self.material, DistrictMaterial):
            raise TypeError("district tile material is invalid")


@dataclass(frozen=True, slots=True)
class GeneratedDistrict:
    """One validated mission plus presentation-safe tile material metadata."""

    challenge: ChallengeDefinition
    mission: MissionData
    tiles: tuple[DistrictTile, ...]
    layout_hash: str

    def __post_init__(self) -> None:
        if not isinstance(self.challenge, ChallengeDefinition):
            raise TypeError("generated district challenge is invalid")
        if not isinstance(self.mission, MissionData) or self.mission.mission_id != "terminal":
            raise ValueError("generated district must materialise a Terminal mission")
        if not isinstance(self.tiles, tuple) or len(self.tiles) != DISTRICT_TILE_COUNT**2:
            raise ValueError("generated district must contain one complete tile grid")
        expected = tuple(
            (x, y) for y in range(DISTRICT_TILE_COUNT) for x in range(DISTRICT_TILE_COUNT)
        )
        if tuple((tile.x, tile.y) for tile in self.tiles) != expected:
            raise ValueError("generated district tiles must be row-major and complete")
        if not isinstance(self.layout_hash, str) or len(self.layout_hash) != 64:
            raise ValueError("generated district layout hash must be a BLAKE2b-256 hex digest")


def daily_challenge(day: str, contract_index: int = 0) -> ChallengeDefinition:
    """Build one ISO-date-selected challenge without reading a host clock."""
    if not _is_iso_date(day):
        raise ValueError("daily challenge requires a valid ISO calendar date")
    challenge_id = f"daily_{day.replace('-', '_')}"
    return _challenge(ChallengeMode.DAILY, challenge_id, _hash_seed(day), contract_index)


def practice_challenge(seed: int, contract_index: int = 0) -> ChallengeDefinition:
    """Build one explicit-seed challenge without a wall-clock dependency."""
    if not isinstance(seed, int) or isinstance(seed, bool) or not 0 <= seed <= _MAX_UINT64:
        raise ValueError("practice challenge seed must fit unsigned 64-bit range")
    return _challenge(ChallengeMode.PRACTICE, f"practice_{seed}", seed, contract_index)


def generate_district(challenge: ChallengeDefinition) -> GeneratedDistrict:
    """Generate one bounded, replay-regenerable Terminal modular district."""
    if not isinstance(challenge, ChallengeDefinition):
        raise TypeError("district generation requires a challenge definition")
    lane_x = 10 + _bounded(challenge.seed, 0, 12)
    lane_y = 10 + _bounded(challenge.seed, 1, 12)
    tiles = tuple(
        DistrictTile(x, y, _tile_material(x, y, lane_x, lane_y))
        for y in range(DISTRICT_TILE_COUNT)
        for x in range(DISTRICT_TILE_COUNT)
    )
    mission = MissionData(
        "terminal",
        f"Terminal {challenge.mode.value} / contract {challenge.contract_index + 1}",
        30,
        challenge.seed,
        _bounds(),
        _obstacles(challenge, lane_x, lane_y),
        _covers(challenge, lane_x, lane_y),
        _regions(),
    )
    return GeneratedDistrict(challenge, mission, tiles, _layout_hash(challenge, tiles, mission))


def _challenge(
    mode: ChallengeMode, challenge_id: str, root_seed: int, contract_index: int
) -> ChallengeDefinition:
    if (
        not isinstance(contract_index, int)
        or isinstance(contract_index, bool)
        or contract_index < 0
    ):
        raise ValueError("challenge contract index must be non-negative")
    seed = root_seed
    for index in range(contract_index):
        seed = _derive_seed(seed, index + 1)
    return ChallengeDefinition(mode, challenge_id, seed, DISTRICT_GENERATOR_VERSION, contract_index)


def _is_iso_date(value: object) -> bool:
    """Validate a Gregorian calendar day using only deterministic string arithmetic."""
    if (
        not isinstance(value, str)
        or len(value) != 10
        or value[4] != "-"
        or value[7] != "-"
        or not (value[:4] + value[5:7] + value[8:]).isdigit()
    ):
        return False
    year = int(value[:4])
    month = int(value[5:7])
    day = int(value[8:])
    if not 1 <= month <= 12:
        return False
    days = (
        31,
        29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28,
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    )
    return 1 <= day <= days[month - 1]


def _bounds() -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(-_DISTRICT_HALF_WIDTH),
        WorldSubunits(-_DISTRICT_HALF_WIDTH),
        WorldSubunits(_DISTRICT_HALF_WIDTH),
        WorldSubunits(_DISTRICT_HALF_WIDTH),
    )


def _obstacles(
    challenge: ChallengeDefinition, lane_x: int, lane_y: int
) -> tuple[MissionObstacle, ...]:
    offset = _bounded(challenge.seed, 2, 5) * DISTRICT_TILE_MILLIMETRES
    obstacles = (
        ("northwall", _rectangle(-4_000, 10_000, 4_000, 11_000)),
        ("southwall", _rectangle(-4_000, -11_000, 4_000, -10_000)),
        ("eastcover", _rectangle(7_000, -3_000, 8_000, 3_000)),
        ("westcover", _rectangle(-8_000, -3_000, -7_000, 3_000)),
        (
            "pivot",
            _rectangle(
                (lane_x - 16) * DISTRICT_TILE_MILLIMETRES - 500,
                (lane_y - 16) * DISTRICT_TILE_MILLIMETRES - 500,
                (lane_x - 16) * DISTRICT_TILE_MILLIMETRES + 500,
                (lane_y - 16) * DISTRICT_TILE_MILLIMETRES + 500,
            ),
        ),
        ("contractwall", _rectangle(offset, 5_000, offset + 1_000, 8_000)),
    )
    return tuple(
        MissionObstacle(content_id, bounds, ElevationLayer(0))
        for content_id, bounds in sorted(obstacles)
    )


def _covers(challenge: ChallengeDefinition, lane_x: int, lane_y: int) -> tuple[MissionCover, ...]:
    x = (lane_x - 16) * DISTRICT_TILE_MILLIMETRES
    y = (lane_y - 16) * DISTRICT_TILE_MILLIMETRES
    values = (
        ("cover_a", -4_000, -5_000, -2_000, -5_000, MissionCoverHeight.LOW),
        ("cover_b", 2_000, 5_000, 4_000, 5_000, MissionCoverHeight.HIGH),
        ("cover_c", x - 1_000, y + 1_000, x + 1_000, y + 1_000, MissionCoverHeight.HIGH),
    )
    return tuple(
        MissionCover(
            content_id,
            _position(start_x, start_y),
            _position(end_x, end_y),
            height,
            10_000,
            (
                MissionCoverSlot(_position(start_x + 500, start_y), MissionCoverSide.LEFT),
                MissionCoverSlot(_position(end_x - 500, end_y), MissionCoverSide.RIGHT),
            ),
        )
        for content_id, start_x, start_y, end_x, end_y, height in values
    )


def _regions() -> tuple[MissionRegion, ...]:
    return (
        MissionRegion("extraction", _rectangle(-15_000, -4_000, -12_000, 4_000)),
        MissionRegion("objective_room", _rectangle(11_000, -3_000, 14_000, 3_000)),
    )


def _tile_material(x: int, y: int, lane_x: int, lane_y: int) -> DistrictMaterial:
    if x in (0, DISTRICT_TILE_COUNT - 1) or y in (0, DISTRICT_TILE_COUNT - 1):
        return DistrictMaterial.WALL
    if x == lane_x or y == lane_y:
        return DistrictMaterial.LANE
    if (x + y) % 11 == 0:
        return DistrictMaterial.COVER
    return DistrictMaterial.FLOOR


def _layout_hash(
    challenge: ChallengeDefinition, tiles: tuple[DistrictTile, ...], mission: MissionData
) -> str:
    encoded = "|".join(
        (
            challenge.mode.value,
            challenge.challenge_id,
            str(challenge.seed),
            str(challenge.generator_version),
            str(challenge.contract_index),
            mission.title,
            *(tile.material.value for tile in tiles),
        )
    ).encode("ascii")
    return blake2b(encoded, digest_size=32, person=b"KWI-DISTRICT-V1").hexdigest()


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def _rectangle(minimum_x: int, minimum_y: int, maximum_x: int, maximum_y: int) -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(minimum_x),
        WorldSubunits(minimum_y),
        WorldSubunits(maximum_x),
        WorldSubunits(maximum_y),
    )


def _hash_seed(text: str) -> int:
    return int.from_bytes(
        blake2b(text.encode("ascii"), digest_size=8, person=b"KWI-DAILY-V1").digest(), "big"
    )


def _derive_seed(seed: int, contract_index: int) -> int:
    return _splitmix64(seed ^ contract_index)


def _bounded(seed: int, stream: int, upper_bound: int) -> int:
    if upper_bound <= 0:
        raise ValueError("district random bound must be positive")
    return _splitmix64(seed ^ stream) % upper_bound


def _splitmix64(value: int) -> int:
    value = (value + 0x9E3779B97F4A7C15) & _MAX_UINT64
    value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & _MAX_UINT64
    value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & _MAX_UINT64
    return value ^ (value >> 31)


def _is_identifier(value: str) -> bool:
    return bool(value) and all(
        character.isascii() and (character.islower() or character.isdigit() or character == "_")
        for character in value
    )
