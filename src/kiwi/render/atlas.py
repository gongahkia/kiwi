"""Presentation-only texture atlas loading and deterministic frame lookup."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import pygame

_ASSET_ROOT = Path(__file__).with_name("assets")
_ATLAS_NAME = "glasshouse_atlas.png"


@dataclass(frozen=True, slots=True)
class AtlasFrame:
    """One immutable pixel rectangle identified by a renderer-facing name."""

    name: str
    x: int
    y: int
    width: int
    height: int

    def __post_init__(self) -> None:
        if not isinstance(self.name, str) or not self.name:
            raise ValueError("atlas frame name must be text")
        if any(
            not isinstance(value, int) or isinstance(value, bool)
            for value in (self.x, self.y, self.width, self.height)
        ):
            raise TypeError("atlas frame coordinates must be integers")
        if self.x < 0 or self.y < 0 or self.width <= 0 or self.height <= 0:
            raise ValueError("atlas frame must have non-negative origin and positive size")


@dataclass(frozen=True, slots=True)
class AtlasAnimation:
    """One frame sequence whose phase is derived only from presentation tick."""

    name: str
    frames: tuple[str, ...]
    ticks_per_frame: int

    def __post_init__(self) -> None:
        if not isinstance(self.name, str) or not self.name:
            raise ValueError("atlas animation name must be text")
        if not isinstance(self.frames, tuple) or not self.frames:
            raise ValueError("atlas animation requires immutable frames")
        if any(not isinstance(frame, str) or not frame for frame in self.frames):
            raise ValueError("atlas animation frame names must be text")
        if (
            not isinstance(self.ticks_per_frame, int)
            or isinstance(self.ticks_per_frame, bool)
            or self.ticks_per_frame <= 0
        ):
            raise ValueError("atlas animation ticks per frame must be positive")


GLASSHOUSE_ATLAS_FRAMES = (
    AtlasFrame("operative", 48, 45, 270, 300),
    AtlasFrame("operative_alert", 350, 45, 270, 300),
    AtlasFrame("hostile", 32, 375, 270, 280),
    AtlasFrame("cover", 382, 375, 360, 290),
    AtlasFrame("wall", 660, 680, 540, 260),
    AtlasFrame("objective", 840, 340, 360, 330),
    AtlasFrame("projectile", 45, 1_015, 270, 150),
    AtlasFrame("impact", 650, 985, 300, 230),
    AtlasFrame("floor", 70, 680, 520, 300),
)
GLASSHOUSE_ATLAS_ANIMATIONS = (
    AtlasAnimation("operative_idle", ("operative", "operative_alert"), 10),
    AtlasAnimation("impact", ("impact", "projectile", "impact"), 2),
)


class TextureAtlas:
    """A cached pygame atlas with explicit grid-frame extraction."""

    def __init__(self, image: pygame.Surface) -> None:
        if not isinstance(image, pygame.Surface):
            raise TypeError("texture atlas requires a pygame surface")
        self._image = image.convert()
        self._frames = {frame.name: frame for frame in GLASSHOUSE_ATLAS_FRAMES}
        self._cache: dict[tuple[str, int, tuple[int, int, int]], pygame.Surface] = {}

    def frame(self, name: str, size: int, tint: tuple[int, int, int]) -> pygame.Surface:
        """Return one nearest-neighbour tinted presentation frame."""
        if not isinstance(name, str) or name not in self._frames:
            raise ValueError("texture atlas frame is unavailable")
        if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
            raise ValueError("texture atlas frame size must be positive")
        _validate_tint(tint)
        key = (name, size, tint)
        cached = self._cache.get(key)
        if cached is not None:
            return cached
        source = self._frames[name]
        if (
            source.x + source.width > self._image.get_width()
            or source.y + source.height > self._image.get_height()
        ):
            raise ValueError("texture atlas frame exceeds source image")
        crop = self._image.subsurface(
            pygame.Rect(
                source.x,
                source.y,
                source.width,
                source.height,
            )
        ).copy()
        crop = pygame.transform.scale(crop, (size, size))
        crop.fill(tint, special_flags=pygame.BLEND_RGB_MULT)
        self._cache[key] = crop
        return crop

    def animation_frame(
        self, name: str, tick: int, size: int, tint: tuple[int, int, int]
    ) -> pygame.Surface:
        """Return one deterministic display-animation frame for a recorded tick."""
        if not isinstance(tick, int) or isinstance(tick, bool) or tick < 0:
            raise ValueError("atlas animation tick must be non-negative")
        animation = next((item for item in GLASSHOUSE_ATLAS_ANIMATIONS if item.name == name), None)
        if animation is None:
            raise ValueError("texture atlas animation is unavailable")
        frame = animation.frames[(tick // animation.ticks_per_frame) % len(animation.frames)]
        return self.frame(frame, size, tint)


def load_glasshouse_atlas() -> TextureAtlas | None:
    """Load generated source art; absence is a non-authoritative visual fallback."""
    try:
        return TextureAtlas(pygame.image.load(_ASSET_ROOT / _ATLAS_NAME))
    except (pygame.error, FileNotFoundError):
        return None


def _validate_tint(tint: tuple[int, int, int]) -> None:
    if not isinstance(tint, tuple) or len(tint) != 3:
        raise ValueError("texture tint must be an RGB tuple")
    if any(
        not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 255
        for value in tint
    ):
        raise ValueError("texture tint components must be between zero and 255")
