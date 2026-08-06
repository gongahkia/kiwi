"""Minimal pygame-ce window, logical canvas, and tactical renderer."""

from __future__ import annotations

from dataclasses import dataclass

import pygame

from kiwi.render.atlas import TextureAtlas
from kiwi.render.camera import (
    Camera,
    Projection,
    isometric_depth_key,
    radius_to_canvas,
    rectangle_polygon_to_canvas,
    rectangle_to_canvas,
    world_to_canvas,
)
from kiwi.render.pygame_lifecycle import initialise_pygame
from kiwi.sim.snapshot import (
    PresentationCover,
    PresentationImpact,
    PresentationOperative,
    PresentationPoint,
    PresentationRectangle,
    PresentationSnapshot,
)

DEFAULT_WINDOW_SIZE = (960, 540)
DEFAULT_LOGICAL_CANVAS_SIZE = (480, 270)
WINDOW_TITLE = "Kiwi"
BACKGROUND_COLOR = (10, 14, 19)
MAP_FILL_COLOR = (25, 42, 48)
MAP_BORDER_COLOR = (88, 150, 144)
OBSTACLE_COLOR = (53, 69, 75)
PATH_COLOR = (245, 189, 74)
OPERATIVE_COLOR = (111, 216, 168)
OBJECTIVE_COLOR = (239, 99, 99)
VISIBILITY_RANGE_COLOR = (68, 119, 142)
VISIBLE_GEOMETRY_COLOR = (111, 174, 196)
CONTACT_UNCERTAINTY_COLOR = (230, 145, 102)
CONTACT_MARKER_COLOR = (255, 214, 130)
COVER_LOW_COLOR = (198, 152, 77)
COVER_HIGH_COLOR = (95, 191, 162)
COVER_DAMAGED_COLOR = (102, 61, 64)
COVER_THREAT_DIRECTION_COLOR = (244, 117, 94)
COVER_SLOT_EMPTY_COLOR = (192, 201, 191)
COVER_SLOT_OCCUPIED_COLOR = (255, 237, 152)
PROJECTILE_COLOR = (255, 231, 112)
IMPACT_OBSTACLE_COLOR = (219, 229, 234)
IMPACT_COVER_COLOR = (255, 175, 84)
IMPACT_OPERATIVE_COLOR = (239, 99, 99)
AIM_COLOR = (111, 216, 238)
SUPPRESSION_COLOR = (244, 117, 94)
OPERATIVE_RADIUS_PIXELS = 4
OBJECTIVE_RADIUS_PIXELS = 6
CONTACT_RADIUS_PIXELS = 2
PROJECTILE_RADIUS_PIXELS = 2
IMPACT_RADIUS_PIXELS = 4
IMPACT_BURST_RADIUS_PIXELS = 7
AIM_INDICATOR_MAX_HEIGHT_PIXELS = 4
SUPPRESSION_RING_MIN_RADIUS_PIXELS = 7
SUPPRESSION_RING_MAX_RADIUS_PIXELS = 9
COVER_LOW_WIDTH_PIXELS = 2
COVER_HIGH_WIDTH_PIXELS = 3
COVER_SLOT_EMPTY_RADIUS_PIXELS = 3
COVER_SLOT_OCCUPIED_RADIUS_PIXELS = 6
COVER_THREAT_DIRECTION_LENGTH_PIXELS = 10


@dataclass(frozen=True, slots=True)
class TacticalPalette:
    """One complete renderer-only tactical palette, including map and sprite tints."""

    background: tuple[int, int, int] = BACKGROUND_COLOR
    map_fill: tuple[int, int, int] = MAP_FILL_COLOR
    map_border: tuple[int, int, int] = MAP_BORDER_COLOR
    obstacle: tuple[int, int, int] = OBSTACLE_COLOR
    path: tuple[int, int, int] = PATH_COLOR
    operative: tuple[int, int, int] = OPERATIVE_COLOR
    hostile: tuple[int, int, int] = OBJECTIVE_COLOR
    objective: tuple[int, int, int] = OBJECTIVE_COLOR
    visibility: tuple[int, int, int] = VISIBILITY_RANGE_COLOR
    visible_geometry: tuple[int, int, int] = VISIBLE_GEOMETRY_COLOR
    contact: tuple[int, int, int] = CONTACT_MARKER_COLOR
    contact_uncertainty: tuple[int, int, int] = CONTACT_UNCERTAINTY_COLOR
    projectile: tuple[int, int, int] = PROJECTILE_COLOR
    impact: tuple[int, int, int] = IMPACT_OPERATIVE_COLOR
    cover_low: tuple[int, int, int] = COVER_LOW_COLOR
    cover_high: tuple[int, int, int] = COVER_HIGH_COLOR
    cover_damaged: tuple[int, int, int] = COVER_DAMAGED_COLOR

    def __post_init__(self) -> None:
        for color in (
            self.background,
            self.map_fill,
            self.map_border,
            self.obstacle,
            self.path,
            self.operative,
            self.hostile,
            self.objective,
            self.visibility,
            self.visible_geometry,
            self.contact,
            self.contact_uncertainty,
            self.projectile,
            self.impact,
            self.cover_low,
            self.cover_high,
            self.cover_damaged,
        ):
            if not isinstance(color, tuple) or len(color) != 3:
                raise ValueError("tactical palette colors must be RGB tuples")
            if any(
                not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 255
                for value in color
            ):
                raise ValueError("tactical palette colors must be between zero and 255")


DEFAULT_TACTICAL_PALETTE = TacticalPalette()


@dataclass(frozen=True, slots=True)
class PygameWindow:
    """One mutable pygame surface pair behind immutable display dimensions."""

    window: pygame.Surface
    logical_canvas: pygame.Surface
    logical_size: tuple[int, int]

    def __post_init__(self) -> None:
        if not isinstance(self.window, pygame.Surface):
            raise ValueError("pygame window requires a pygame surface")
        if not isinstance(self.logical_canvas, pygame.Surface):
            raise ValueError("logical canvas requires a pygame surface")
        if self.logical_canvas.get_size() != self.logical_size:
            raise ValueError("logical canvas size must match its surface")
        _size(self.logical_size, "logical canvas")


def open_pygame_window(
    window_size: tuple[int, int] = DEFAULT_WINDOW_SIZE,
    logical_size: tuple[int, int] = DEFAULT_LOGICAL_CANVAS_SIZE,
) -> PygameWindow:
    """Initialise pygame-ce and create a window with a separate logical canvas."""
    _size(window_size, "window")
    _size(logical_size, "logical canvas")
    initialise_pygame()
    pygame.display.set_caption(WINDOW_TITLE)
    return PygameWindow(
        window=pygame.display.set_mode(window_size),
        logical_canvas=pygame.Surface(logical_size),
        logical_size=logical_size,
    )


def render_basic_map(
    logical_canvas: pygame.Surface,
    snapshot: PresentationSnapshot,
    camera: Camera,
    palette: TacticalPalette = DEFAULT_TACTICAL_PALETTE,
) -> None:
    """Draw the map bounds only; entities, obstacles, and overlays follow later."""
    if not isinstance(logical_canvas, pygame.Surface):
        raise TypeError("map rendering requires a pygame surface")
    if not isinstance(snapshot, PresentationSnapshot):
        raise TypeError("map rendering requires a presentation snapshot")
    if not isinstance(camera, Camera):
        raise TypeError("map rendering requires a camera")
    if not isinstance(palette, TacticalPalette):
        raise TypeError("map rendering requires a tactical palette")
    logical_canvas.fill(palette.background)
    if snapshot.map_geometry is None:
        return
    _draw_map_rectangle(logical_canvas, snapshot.map_geometry.bounds, camera, palette.map_fill)
    _draw_map_rectangle(
        logical_canvas, snapshot.map_geometry.bounds, camera, palette.map_border, width=1
    )


def render_tactical_view(
    logical_canvas: pygame.Surface,
    snapshot: PresentationSnapshot,
    camera: Camera,
    *,
    palette: TacticalPalette = DEFAULT_TACTICAL_PALETTE,
    atlas: TextureAtlas | None = None,
) -> None:
    """Render copied map, overlays, operatives, projectiles, and current impacts."""
    if not isinstance(palette, TacticalPalette):
        raise TypeError("tactical renderer palette is invalid")
    if atlas is not None and not isinstance(atlas, TextureAtlas):
        raise TypeError("tactical renderer atlas is invalid")
    render_basic_map(logical_canvas, snapshot, camera, palette)
    if snapshot.map_geometry is not None:
        for map_obstacle in snapshot.map_geometry.obstacles:
            _draw_map_rectangle(logical_canvas, map_obstacle.bounds, camera, palette.obstacle)
    for overlay in snapshot.visibility_overlays:
        observer = world_to_canvas(overlay.observer, logical_canvas.get_size(), camera)
        radius = radius_to_canvas(overlay.sensor_radius, camera)
        if radius > 0:
            pygame.draw.circle(logical_canvas, palette.visibility, observer, radius, width=1)
        for visible_obstacle in overlay.visible_obstacles:
            pygame.draw.rect(
                logical_canvas,
                palette.visible_geometry,
                rectangle_to_canvas(visible_obstacle.bounds, logical_canvas.get_size(), camera),
                width=1,
            )
    for cover in snapshot.covers:
        _render_cover(logical_canvas, cover, snapshot, camera, palette)
    for contact in snapshot.contacts:
        estimated_position = world_to_canvas(
            contact.estimated_position,
            logical_canvas.get_size(),
            camera,
        )
        uncertainty_radius = radius_to_canvas(contact.uncertainty_radius, camera)
        if uncertainty_radius > 0:
            pygame.draw.circle(
                logical_canvas,
                palette.contact_uncertainty,
                estimated_position,
                max(1, uncertainty_radius),
                width=1,
            )
        pygame.draw.circle(
            logical_canvas,
            palette.contact,
            estimated_position,
            CONTACT_RADIUS_PIXELS,
        )
    for operative in snapshot.operatives:
        if len(operative.path) > 1:
            pygame.draw.lines(
                logical_canvas,
                palette.path,
                False,
                tuple(
                    world_to_canvas(point, logical_canvas.get_size(), camera)
                    for point in operative.path
                ),
                width=1,
            )
    if snapshot.objective_marker is not None:
        _render_sprite_or_circle(
            logical_canvas,
            atlas,
            "objective",
            snapshot.tick,
            palette.objective,
            world_to_canvas(snapshot.objective_marker, logical_canvas.get_size(), camera),
            OBJECTIVE_RADIUS_PIXELS * 3,
            outlined=True,
        )
    for operative in sorted(
        snapshot.operatives,
        key=lambda item: isometric_depth_key(item.position, item.entity_id, camera),
    ):
        _render_operative_combat_state(logical_canvas, operative, camera)
        _render_sprite_or_circle(
            logical_canvas,
            atlas,
            "operative_idle",
            snapshot.tick + operative.entity_id,
            palette.operative if operative.entity_id % 2 else palette.hostile,
            world_to_canvas(operative.position, logical_canvas.get_size(), camera),
            OPERATIVE_RADIUS_PIXELS * 3,
            animation=True,
        )
    for projectile in snapshot.projectiles:
        _render_sprite_or_circle(
            logical_canvas,
            atlas,
            "projectile",
            snapshot.tick,
            palette.projectile,
            world_to_canvas(projectile.position, logical_canvas.get_size(), camera),
            PROJECTILE_RADIUS_PIXELS * 3,
        )
    for impact in snapshot.impacts:
        _render_impact(logical_canvas, impact, camera, palette, atlas, snapshot.tick)


def _draw_map_rectangle(
    logical_canvas: pygame.Surface,
    rectangle: PresentationRectangle,
    camera: Camera,
    color: tuple[int, int, int],
    *,
    width: int = 0,
) -> None:
    if camera.projection is Projection.ISOMETRIC:
        pygame.draw.polygon(
            logical_canvas,
            color,
            rectangle_polygon_to_canvas(rectangle, logical_canvas.get_size(), camera),
            width=width,
        )
        return
    pygame.draw.rect(
        logical_canvas,
        color,
        rectangle_to_canvas(rectangle, logical_canvas.get_size(), camera),
        width=width,
    )


def _render_sprite_or_circle(
    logical_canvas: pygame.Surface,
    atlas: TextureAtlas | None,
    frame: str,
    tick: int,
    tint: tuple[int, int, int],
    position: tuple[int, int],
    size: int,
    *,
    animation: bool = False,
    outlined: bool = False,
) -> None:
    if atlas is None:
        pygame.draw.circle(
            logical_canvas,
            tint,
            position,
            max(1, (size + 2) // 3),
            width=1 if outlined else 0,
        )
        return
    image = (
        atlas.animation_frame(frame, tick, size, tint)
        if animation
        else atlas.frame(frame, size, tint)
    )
    logical_canvas.blit(image, image.get_rect(center=position))


def _render_operative_combat_state(
    logical_canvas: pygame.Surface,
    operative: PresentationOperative,
    camera: Camera,
) -> None:
    position = world_to_canvas(operative.position, logical_canvas.get_size(), camera)
    if operative.aim_quality_basis_points > 0:
        height = max(
            1,
            operative.aim_quality_basis_points * AIM_INDICATOR_MAX_HEIGHT_PIXELS // 10_000,
        )
        start = (position[0], position[1] - OPERATIVE_RADIUS_PIXELS - 1)
        pygame.draw.line(logical_canvas, AIM_COLOR, start, (start[0], start[1] - height))
    if operative.suppression_basis_points > 0:
        radius = SUPPRESSION_RING_MIN_RADIUS_PIXELS + (
            operative.suppression_basis_points
            * (SUPPRESSION_RING_MAX_RADIUS_PIXELS - SUPPRESSION_RING_MIN_RADIUS_PIXELS)
            // 10_000
        )
        pygame.draw.circle(logical_canvas, SUPPRESSION_COLOR, position, radius, width=1)


def _render_impact(
    logical_canvas: pygame.Surface,
    impact: PresentationImpact,
    camera: Camera,
    palette: TacticalPalette,
    atlas: TextureAtlas | None,
    tick: int,
) -> None:
    color = {
        "obstacle": IMPACT_OBSTACLE_COLOR,
        "cover": IMPACT_COVER_COLOR,
        "operative": IMPACT_OPERATIVE_COLOR,
    }[impact.collision_kind]
    position = world_to_canvas(impact.position, logical_canvas.get_size(), camera)
    if atlas is not None:
        _render_sprite_or_circle(
            logical_canvas,
            atlas,
            "impact",
            tick,
            palette.impact,
            position,
            IMPACT_BURST_RADIUS_PIXELS * 3,
            animation=True,
        )
        return
    pygame.draw.line(
        logical_canvas,
        color,
        (position[0] - IMPACT_RADIUS_PIXELS, position[1]),
        (position[0] + IMPACT_RADIUS_PIXELS, position[1]),
    )
    pygame.draw.line(
        logical_canvas,
        color,
        (position[0], position[1] - IMPACT_RADIUS_PIXELS),
        (position[0], position[1] + IMPACT_RADIUS_PIXELS),
    )
    pygame.draw.circle(logical_canvas, color, position, IMPACT_BURST_RADIUS_PIXELS, width=1)


def _render_cover(
    logical_canvas: pygame.Surface,
    cover: PresentationCover,
    snapshot: PresentationSnapshot,
    camera: Camera,
    palette: TacticalPalette,
) -> None:
    centre = _cover_centre(cover)
    for contact in snapshot.contacts:
        if contact.estimated_position.elevation == cover.start.elevation:
            _render_cover_threat_direction(
                logical_canvas,
                centre,
                contact.estimated_position,
                camera,
            )
    pygame.draw.line(
        logical_canvas,
        _cover_quality_color(
            cover,
            palette.cover_high if cover.height == "high" else palette.cover_low,
            palette.cover_damaged,
        ),
        world_to_canvas(cover.start, logical_canvas.get_size(), camera),
        world_to_canvas(cover.end, logical_canvas.get_size(), camera),
        COVER_HIGH_WIDTH_PIXELS if cover.height == "high" else COVER_LOW_WIDTH_PIXELS,
    )
    for slot in cover.slots:
        pygame.draw.circle(
            logical_canvas,
            COVER_SLOT_OCCUPIED_COLOR
            if slot.occupant_entity_id is not None
            else COVER_SLOT_EMPTY_COLOR,
            world_to_canvas(slot.position, logical_canvas.get_size(), camera),
            COVER_SLOT_OCCUPIED_RADIUS_PIXELS
            if slot.occupant_entity_id is not None
            else COVER_SLOT_EMPTY_RADIUS_PIXELS,
            width=1,
        )


def _cover_centre(cover: PresentationCover) -> PresentationPoint:
    if not isinstance(cover, PresentationCover):
        raise TypeError("cover rendering requires a presentation cover")
    return PresentationPoint(
        (cover.start.x + cover.end.x) / 2,
        (cover.start.y + cover.end.y) / 2,
        cover.start.elevation,
    )


def _cover_quality_color(
    cover: PresentationCover,
    source: tuple[int, int, int] | None = None,
    damaged: tuple[int, int, int] = COVER_DAMAGED_COLOR,
) -> tuple[int, int, int]:
    if not isinstance(cover, PresentationCover):
        raise TypeError("cover rendering requires a presentation cover")
    if source is None:
        source = COVER_HIGH_COLOR if cover.height == "high" else COVER_LOW_COLOR
    _validate_color(source)
    _validate_color(damaged)
    integrity = cover.integrity_basis_points
    return (
        (source[0] * integrity + damaged[0] * (10_000 - integrity)) // 10_000,
        (source[1] * integrity + damaged[1] * (10_000 - integrity)) // 10_000,
        (source[2] * integrity + damaged[2] * (10_000 - integrity)) // 10_000,
    )


def _validate_color(color: tuple[int, int, int]) -> None:
    if not isinstance(color, tuple) or len(color) != 3:
        raise ValueError("tactical palette colors must be RGB tuples")
    if any(
        not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 255
        for value in color
    ):
        raise ValueError("tactical palette colors must be between zero and 255")


def _render_cover_threat_direction(
    logical_canvas: pygame.Surface,
    centre: PresentationPoint,
    threat: PresentationPoint,
    camera: Camera,
) -> None:
    start = world_to_canvas(centre, logical_canvas.get_size(), camera)
    target = world_to_canvas(threat, logical_canvas.get_size(), camera)
    delta_x = target[0] - start[0]
    delta_y = target[1] - start[1]
    dominant_distance = max(abs(delta_x), abs(delta_y))
    if dominant_distance == 0:
        return
    tip = (
        start[0] + round(delta_x * COVER_THREAT_DIRECTION_LENGTH_PIXELS / dominant_distance),
        start[1] + round(delta_y * COVER_THREAT_DIRECTION_LENGTH_PIXELS / dominant_distance),
    )
    pygame.draw.line(logical_canvas, COVER_THREAT_DIRECTION_COLOR, start, tip, width=1)
    pygame.draw.circle(logical_canvas, COVER_THREAT_DIRECTION_COLOR, tip, 1)


def present(window: PygameWindow) -> None:
    """Scale the logical canvas into the current window and present one frame."""
    if not isinstance(window, PygameWindow):
        raise TypeError("presentation requires a pygame window")
    window_size = window.window.get_size()
    if window_size == window.logical_size:
        window.window.blit(window.logical_canvas, (0, 0))
    else:
        window.window.blit(pygame.transform.scale(window.logical_canvas, window_size), (0, 0))
    pygame.display.flip()


def _size(value: tuple[int, int], label: str) -> tuple[int, int]:
    if not isinstance(value, tuple) or len(value) != 2:
        raise ValueError(f"{label} size must be a two-item tuple")
    width, height = value
    if any(not isinstance(component, int) or isinstance(component, bool) for component in value):
        raise ValueError(f"{label} dimensions must be integers")
    if width <= 0 or height <= 0:
        raise ValueError(f"{label} dimensions must be positive")
    return width, height
