"""One-shot pygame audio playback for copied Glasshouse mission event cues."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import pygame

from kiwi.ui.glasshouse_mission import GlasshouseSoundCue, GlasshouseSoundCueKind

_DEFAULT_SAMPLE_RATE = 22_050
_MIXER_BUFFER_SIZE = 256


@dataclass(frozen=True, slots=True)
class _CueProfile:
    filename: str
    volume: float


_CUE_PROFILES = (
    (GlasshouseSoundCueKind.FIRE, _CueProfile("cue_fire.wav", 0.18)),
    (GlasshouseSoundCueKind.IMPACT, _CueProfile("cue_impact.wav", 0.16)),
    (GlasshouseSoundCueKind.INJURY, _CueProfile("cue_injury.wav", 0.14)),
    (
        GlasshouseSoundCueKind.OBJECTIVE_RETRIEVED,
        _CueProfile("cue_objective_retrieved.wav", 0.14),
    ),
    (
        GlasshouseSoundCueKind.OBJECTIVE_EXTRACTED,
        _CueProfile("cue_objective_extracted.wav", 0.16),
    ),
    (GlasshouseSoundCueKind.LOCKDOWN, _CueProfile("cue_lockdown.wav", 0.16)),
)
_ASSET_ROOT = Path(__file__).with_name("assets")


class GlasshouseSoundPlayer:
    """Play each copied event cue at most once for one presentation session."""

    def __init__(self) -> None:
        self._played_event_ids: set[int] = set()
        self._sounds: tuple[tuple[GlasshouseSoundCueKind, pygame.mixer.Sound], ...] = ()

    def play(self, cues: tuple[GlasshouseSoundCue, ...]) -> tuple[GlasshouseSoundCue, ...]:
        """Attempt non-authoritative playback and return cues accepted this session."""
        if not isinstance(cues, tuple) or any(
            not isinstance(cue, GlasshouseSoundCue) for cue in cues
        ):
            raise TypeError("Glasshouse sound playback requires immutable sound cues")
        if not _ensure_mixer():
            return ()
        played: list[GlasshouseSoundCue] = []
        for cue in cues:
            if cue.event_id in self._played_event_ids:
                continue
            sound = self._sound_for(cue.kind)
            if sound is None:
                continue
            sound.play()
            self._played_event_ids.add(cue.event_id)
            played.append(cue)
        return tuple(played)

    def _sound_for(self, kind: GlasshouseSoundCueKind) -> pygame.mixer.Sound | None:
        for stored_kind, sound in self._sounds:
            if stored_kind is kind:
                return sound
        mixer = pygame.mixer.get_init()
        if mixer is None or mixer[1] != -16 or mixer[2] not in (1, 2):
            return None
        profile = _cue_profile(kind)
        try:
            sound = pygame.mixer.Sound(str(_ASSET_ROOT / profile.filename))
        except (pygame.error, FileNotFoundError):
            return None
        sound.set_volume(profile.volume)
        self._sounds = (*self._sounds, (kind, sound))
        return sound


def _ensure_mixer() -> bool:
    if pygame.mixer.get_init() is not None:
        return True
    try:
        pygame.mixer.init(
            frequency=_DEFAULT_SAMPLE_RATE,
            size=-16,
            channels=1,
            buffer=_MIXER_BUFFER_SIZE,
        )
    except pygame.error:
        return False
    return pygame.mixer.get_init() is not None


def _cue_profile(kind: GlasshouseSoundCueKind) -> _CueProfile:
    for stored_kind, profile in _CUE_PROFILES:
        if stored_kind is kind:
            return profile
    raise AssertionError("Glasshouse sound cue kind has no tone profile")
