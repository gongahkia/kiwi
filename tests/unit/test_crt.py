from __future__ import annotations

import pygame

from kiwi.render.crt import CrtCompositor


def test_crt_compositor_is_optional_and_presentation_only() -> None:
    surface = pygame.Surface((64, 48))
    surface.fill((40, 50, 60))
    untouched = surface.copy()
    compositor = CrtCompositor()

    compositor.apply(surface, (111, 216, 238), 0, enabled=False, reduced_flicker=False)
    assert pygame.image.tobytes(surface, "RGB") == pygame.image.tobytes(untouched, "RGB")

    compositor.apply(surface, (111, 216, 238), 0, enabled=True, reduced_flicker=True)
    assert pygame.image.tobytes(surface, "RGB") != pygame.image.tobytes(untouched, "RGB")
