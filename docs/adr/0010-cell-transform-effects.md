# ADR-0010: Bounded Cell-Transform Effects

- Status: Accepted
- Date: 2026-07-31

## Context

The effects product surface includes bounded cell displacement, but lifecycle API v1 only permits copied cell observation. A kinetic preset must alter presentation without mutating terminal cells or gaining renderer access.

## Decision

Manifest API v1 adds two optional capabilities:

- `cell_transform` gates `transform_cell(effect, context, cell)`;
- `visual_state` gates `needs_redraw(effect, context)`.

`visual_state` requires `cell_transform` on the same manifest.

`transform_cell` receives the existing copied visual-cell record and may return `nil` or an exact scalar transform `{ offset_x, offset_y }`. Both offsets are finite normalized cell units in the inclusive range `-1..1`. The host applies enabled transforms in stable effect order, adds each component, clamps the result to the same range, and passes only the final copy to the renderer. It neither exposes nor changes terminal state.

`needs_redraw` returns a boolean. It lets visual-only state request a full presentation redraw while active; it does not create semantic damage. The renderer opens one bounded visual frame for a transform-capable chain, scopes callback limits to that frame, and closes it even when rendering fails.

This API does not add shaders, render-target access, cell text changes, retained frame buffers, scale, rotation, opacity, or arbitrary graphics state.

## Consequences

Positive:

- kinetic motion stays inside the public effect host boundary;
- terminal and recording isolation remains testable;
- active visual motion can redraw without falsifying semantic damage.

Negative:

- active transform effects may require full presentation redraws;
- API v1 initially supports only bounded translation.

## Rejected alternatives

### Mutate terminal cells with visual offsets

Rejected because offsets would enter terminal semantics and recordings.

### Add kinetic branches to the renderer

Rejected because built-in presets must use the shared effect API.

### Return unrestricted drawing callbacks

Rejected because callbacks would retain renderer authority and bypass bounds.
