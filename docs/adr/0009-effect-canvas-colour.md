# ADR-0009: Bounded Effect Canvas Colours

- Status: Accepted
- Date: 2026-07-31

## Context

Canvas-hook API v1 exposes only bounded geometry primitives. Built-in overlays need a deterministic way to choose an overlay colour without receiving the graphics namespace, shader access, render-target control, or mutable renderer state.

## Decision

`canvas:fill_rect`, `canvas:line`, and `canvas:text` accept an optional colour record with finite `red`, `green`, `blue`, and `alpha` components in the inclusive range `0..1`. The generic `canvas:draw` form accepts the same optional `colour` field.

The host validates and copies the colour with every operation. The renderer applies it only while the callback's existing nested graphics-state scope is active. Effects cannot read graphics state, replace render targets, set shaders or blend modes, allocate resources, or retain drawing authority after the callback returns.

## Consequences

Positive:

- built-in procedural overlays can preserve readable contrast;
- colours remain scalar, serialisable, bounded, and deterministic;
- canvas isolation remains unchanged.

Negative:

- the facade needs explicit colour validation and test coverage;
- full shader, blending, and temporal-buffer effects remain outside API v1.

## Rejected alternatives

### Expose `love.graphics.setColor`

Rejected because it leaks unrestricted renderer authority into effect callbacks.

### Add CRT-specific renderer drawing

Rejected because presets must use the shared public effect API.

