"""Versioned deterministic random streams for authoritative simulation."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum

from kiwi.domain.ids import MAX_STABLE_ID

RANDOM_ALGORITHM_VERSION = 1
_UINT64_MASK = (1 << 64) - 1
_UINT32_MASK = (1 << 32) - 1
_PCG_MULTIPLIER = 6_364_136_223_846_793_005
_PCG_INCREMENT = 1_442_695_040_888_963_407
_SPLITMIX_GAMMA = 0x9E3779B97F4A7C15


class RandomStreamId(IntEnum):
    """Independent named streams with stable seed-derivation order."""

    WEAPON_DISPERSION = 0
    DAMAGE_VARIATION = 1
    SCENARIO_SPAWN = 2
    ENEMY_POLICY = 3


@dataclass(frozen=True, slots=True)
class MissionSeed:
    """One unsigned 64-bit root seed for a mission run."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool):
            raise ValueError("mission seed must be an integer")
        if not 0 <= self.value <= _UINT64_MASK:
            raise ValueError("mission seed must fit unsigned 64-bit range")


@dataclass(frozen=True, slots=True)
class RandomPurpose:
    """A stable machine-readable explanation label for one random draw."""

    value: str

    def __post_init__(self) -> None:
        if (
            not isinstance(self.value, str)
            or not self.value
            or not self.value.isascii()
            or not self.value.isidentifier()
            or self.value != self.value.lower()
        ):
            raise ValueError("random purpose must be a non-empty lowercase ASCII identifier")


@dataclass(frozen=True, slots=True)
class RandomStreamState:
    """PCG32 state and the next raw draw index for one named stream."""

    state: int
    next_draw_index: int = 0

    def __post_init__(self) -> None:
        if not isinstance(self.state, int) or isinstance(self.state, bool):
            raise ValueError("random stream state must be an integer")
        if not 0 <= self.state <= _UINT64_MASK:
            raise ValueError("random stream state must fit unsigned 64-bit range")
        if not isinstance(self.next_draw_index, int) or isinstance(self.next_draw_index, bool):
            raise ValueError("random draw index must be an integer")
        if not 0 <= self.next_draw_index <= MAX_STABLE_ID + 1:
            raise ValueError("random draw index must fit non-negative signed 64-bit range")


@dataclass(frozen=True, slots=True)
class RandomStreams:
    """Canonical root seed and one independent state for each named stream."""

    seed: MissionSeed
    states: tuple[RandomStreamState, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.seed, MissionSeed):
            raise ValueError("random streams require a mission seed")
        if not isinstance(self.states, tuple):
            raise ValueError("random streams require an immutable state tuple")
        if len(self.states) != len(RandomStreamId):
            raise ValueError("random streams require one state for every stream ID")
        for state in self.states:
            if not isinstance(state, RandomStreamState):
                raise ValueError("random streams require random stream states")

    @classmethod
    def from_seed(cls, seed: MissionSeed) -> RandomStreams:
        """Derive independent PCG32 states from one root mission seed."""
        if not isinstance(seed, MissionSeed):
            raise ValueError("random stream derivation requires a mission seed")
        return cls(
            seed=seed,
            states=tuple(
                RandomStreamState(_pcg_initial_state(_derive_stream_seed(seed, stream_id)))
                for stream_id in RandomStreamId
            ),
        )

    def stream_state(self, stream_id: RandomStreamId) -> RandomStreamState:
        """Return one named stream state without exposing mutable authority."""
        if not isinstance(stream_id, RandomStreamId):
            raise ValueError("random stream lookup requires a RandomStreamId")
        return self.states[int(stream_id)]


@dataclass(frozen=True, slots=True)
class RandomDraw:
    """A recorded raw uniform draw with its range and causal purpose."""

    stream_id: RandomStreamId
    draw_index: int
    lower_inclusive: int
    upper_inclusive: int
    result: int
    purpose: RandomPurpose

    def __post_init__(self) -> None:
        if not isinstance(self.stream_id, RandomStreamId):
            raise ValueError("random draw requires a RandomStreamId")
        if not isinstance(self.draw_index, int) or isinstance(self.draw_index, bool):
            raise ValueError("random draw index must be an integer")
        if not 0 <= self.draw_index <= MAX_STABLE_ID:
            raise ValueError("random draw index must fit non-negative signed 64-bit range")
        if self.lower_inclusive != 0 or self.upper_inclusive != _UINT32_MASK:
            raise ValueError("raw PCG32 draws must use the unsigned 32-bit range")
        if not isinstance(self.result, int) or isinstance(self.result, bool):
            raise ValueError("random draw result must be an integer")
        if not self.lower_inclusive <= self.result <= self.upper_inclusive:
            raise ValueError("random draw result must fall within its recorded range")
        if not isinstance(self.purpose, RandomPurpose):
            raise ValueError("random draw requires a random purpose")


def default_random_streams() -> RandomStreams:
    """Return the deterministic zero-seed stream manifest for empty test missions."""
    return RandomStreams.from_seed(MissionSeed(0))


def draw_uint32(
    streams: RandomStreams,
    stream_id: RandomStreamId,
    purpose: RandomPurpose,
) -> tuple[int, RandomDraw, RandomStreams]:
    """Advance one named PCG32 stream and record its raw unsigned draw."""
    if not isinstance(streams, RandomStreams):
        raise ValueError("random draw requires random streams")
    if not isinstance(stream_id, RandomStreamId):
        raise ValueError("random draw requires a RandomStreamId")
    if not isinstance(purpose, RandomPurpose):
        raise ValueError("random draw requires a random purpose")
    state = streams.stream_state(stream_id)
    if state.next_draw_index > MAX_STABLE_ID:
        raise ValueError("random draw allocation exhausted")
    result, next_state = _pcg32_next(state.state)
    draw = RandomDraw(
        stream_id=stream_id,
        draw_index=state.next_draw_index,
        lower_inclusive=0,
        upper_inclusive=_UINT32_MASK,
        result=result,
        purpose=purpose,
    )
    index = int(stream_id)
    states = (
        streams.states[:index]
        + (RandomStreamState(next_state, state.next_draw_index + 1),)
        + streams.states[index + 1 :]
    )
    return result, draw, RandomStreams(seed=streams.seed, states=states)


def _derive_stream_seed(seed: MissionSeed, stream_id: RandomStreamId) -> int:
    return _splitmix64((seed.value + _SPLITMIX_GAMMA * (int(stream_id) + 1)) & _UINT64_MASK)


def _splitmix64(value: int) -> int:
    value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9 & _UINT64_MASK
    value = (value ^ (value >> 27)) * 0x94D049BB133111EB & _UINT64_MASK
    return value ^ (value >> 31)


def _pcg_initial_state(seed: int) -> int:
    _, state = _pcg32_next(0)
    _, state = _pcg32_next((state + seed) & _UINT64_MASK)
    return state


def _pcg32_next(state: int) -> tuple[int, int]:
    xorshifted = (((state >> 18) ^ state) >> 27) & _UINT32_MASK
    rotation = state >> 59
    result = ((xorshifted >> rotation) | (xorshifted << ((-rotation) & 31))) & _UINT32_MASK
    next_state = (state * _PCG_MULTIPLIER + _PCG_INCREMENT) & _UINT64_MASK
    return result, next_state
