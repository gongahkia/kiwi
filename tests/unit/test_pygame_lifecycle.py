from __future__ import annotations

from kiwi.render.pygame_lifecycle import (
    initialise_pygame,
    pygame_is_initialised,
    quit_pygame,
)


def test_render_owned_pygame_lifecycle_initialises_and_quits_cleanly() -> None:
    quit_pygame()
    assert not pygame_is_initialised()

    initialise_pygame()

    assert pygame_is_initialised()
    quit_pygame()
    assert not pygame_is_initialised()
