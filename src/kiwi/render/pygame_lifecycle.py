"""pygame-ce process lifecycle owned by presentation code."""

from __future__ import annotations

import pygame


class PygameInitialisationError(RuntimeError):
    """pygame-ce did not enter an initialised state."""


def initialise_pygame() -> None:
    """Initialise pygame-ce without creating a window or touching authority state."""
    if not getattr(pygame, "IS_CE", False):
        raise PygameInitialisationError("Kiwi requires pygame-ce")
    pygame.init()
    if not pygame.get_init():
        pygame.quit()
        raise PygameInitialisationError("pygame-ce did not initialise")


def quit_pygame() -> None:
    """Release pygame-ce process resources; repeated calls are harmless."""
    pygame.quit()


def pygame_is_initialised() -> bool:
    """Return whether pygame-ce currently owns its process-level resources."""
    return pygame.get_init()
