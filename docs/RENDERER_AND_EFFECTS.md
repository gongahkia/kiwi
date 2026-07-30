# Renderer and Effects

## 1. Purpose

Stanczyk’s renderer is a programmable presentation layer over terminal state. It should support unusual visual treatments without turning visual behaviour into terminal semantics.

The default clean renderer is the reference presentation. Every effect is optional.

## 2. Rendering pipeline

Suggested frame pipeline:

```text
terminal snapshot + damage
        ↓
base cell backgrounds
        ↓
glyph and decoration geometry
        ↓
cursor
        ↓
per-cell/per-row effect transforms
        ↓
terminal canvas
        ↓
full-frame effects and post-processing
        ↓
debugger and application overlays
        ↓
window
```

The exact order must be configurable only where semantics remain clear.

## 3. Glyph strategy

### 3.1 Requirements

- explicit font metrics;
- deterministic mapping from cell to glyph placement;
- incremental glyph caching;
- support for ASCII, wide characters, and combining marks;
- missing-glyph fallback;
- no font rasterisation during every frame;
- bounded atlas growth or eviction policy.

The bootstrap renderer loads a configured LÖVE font through an injected graphics API and records integer `cell_width`, `cell_height`, and baseline metrics. A caller may override these metrics when a font has unsuitable nominal advances. The terminal core never loads fonts or observes these metrics.

### 3.2 Atlas

A practical initial design:

- one or more canvases/textures storing rasterised glyphs;
- key by font face, size, style approximation, and grapheme text;
- cache metrics separately;
- add glyphs lazily;
- rebuild or allocate additional pages when full;
- preserve stable atlas coordinates for the life of a page.

The core cell does not know the atlas key.

### 3.3 Font fallback

The initial release may use a configured primary monospace font and a fallback chain. Fallback behaviour must preserve cell width decisions made by the core compatibility layer.

If a glyph cannot be rendered within expected metrics, use a visible replacement glyph and emit a debugger warning.

## 4. Geometry and batching

The renderer should avoid one independent draw call per cell.

Options include:

- SpriteBatch for glyph quads;
- Mesh data grouped by atlas page and shader state;
- row-level cached canvases for mostly static content;
- separate batches for backgrounds and glyphs.

The first implementation should prefer clarity and measurement over a complex retained-mode engine.

## 5. Damage-driven rendering

Renderer updates should be driven by terminal damage and visual-effect needs.

- Clean renderer updates changed rows or cell ranges.
- Cursor-only movement should not rebuild all glyph geometry.
- Full-frame post-processing may redraw the final canvas but should not rebuild semantic geometry.
- Time-based effects may request continuous visual updates while leaving terminal geometry unchanged.

## 6. Effect classes

### 6.1 Event effects

React to semantic events and maintain transient visual state.

Examples:

- bell flash;
- output sparks;
- cursor trails;
- scroll impulses.

### 6.2 Cell transform effects

Adjust visual properties per cell:

- position offset;
- scale;
- rotation;
- opacity;
- colour multiplier;
- reveal mask.

These must not alter cell text or attributes in the terminal model.

### 6.3 Row or region effects

Operate on rows or damage regions:

- wave distortion;
- line settling;
- scroll compression;
- region highlighting.

### 6.4 Post-processing effects

Operate on a rendered canvas:

- scanlines;
- curvature;
- bloom;
- chromatic separation;
- persistence;
- noise;
- e-ink or dot-matrix simulation.

### 6.5 Overlay effects

Draw before or after the terminal:

- procedural frame;
- animated background;
- particles;
- diagnostic labels.

## 7. Deterministic effects

Effects receive:

- semantic event sequence number;
- terminal time;
- visual time;
- seeded PRNG handle;
- immutable event payload;
- immutable terminal snapshot or approved query interface.

An effect manifest declares one of:

- `deterministic`: same state and seed reproduce the same visuals;
- `interactive`: may use wall time but cannot be used for deterministic export without substitution;
- `static`: no time dependence.

Built-in effects should be deterministic unless a clear reason exists otherwise.

## 8. Built-in presets

### 8.1 Clean

Purpose: correctness reference and accessible fallback.

Features:

- no distortion;
- high readability;
- configurable cursor;
- standard colour handling;
- no animation beyond optional cursor blink.

### 8.2 CRT/phosphor

Features:

- subtle scanlines;
- configurable curvature;
- temporal persistence using prior-frame canvas;
- controlled bloom;
- optional chromatic separation;
- reduced-motion and zero-persistence settings;
- intensity bounded to preserve text readability.

### 8.3 Kinetic

Features:

- output events impart bounded impulses to affected cells or rows;
- scroll events create directional settling;
- bell creates a brief global impulse;
- cursor movement may leave a short deterministic trail;
- all motion decays to exact baseline positions.

This preset demonstrates the event architecture rather than merely adding a shader.

## 9. Effect manifests

Conceptual manifest:

```lua
return {
  id = "stanczyk.crt",
  version = "0.1.0",
  api_version = 1,
  determinism = "deterministic",
  capabilities = {
    "post_process",
    "terminal_events"
  },
  parameters = {
    intensity = { type = "number", min = 0, max = 1, default = 0.35 },
    persistence = { type = "number", min = 0, max = 1, default = 0.2 },
    curvature = { type = "number", min = 0, max = 1, default = 0.1 }
  }
}
```

## 10. Failure isolation

Lua effects execute in-process and are trusted in v0.1. Strong security isolation must not be claimed.

The host should still:

- validate manifests;
- wrap hooks with error capture;
- disable a repeatedly failing effect;
- preserve the clean renderer;
- show a precise error;
- avoid corrupting core state.

## 11. Hot reload

Development hot reload may:

- unload effect Lua state;
- revalidate the manifest;
- recreate resources;
- preserve serialisable parameters;
- reset transient visual state.

Hot reload must never reload terminal semantic modules implicitly.

## 12. Reduced motion

Built-in effects must honour a reduced-motion setting.

Reduced-motion behaviour should:

- remove or shorten persistent movement;
- remove rapid flashing;
- retain static visual identity where possible;
- preserve the clean fallback.

## 13. Performance budgets

Suggested classes:

- Class A: no-op or static; negligible per-frame overhead.
- Class B: damage-driven cell or row effects; work proportional to changed cells.
- Class C: full-frame post-processing; fixed number of canvas passes.
- Class D: experimental; allowed to exceed default budgets and clearly labelled.

The host should expose basic timing diagnostics for effects.

## 14. Export considerations

A future deterministic export path should be able to:

- step terminal and visual time at a fixed frame rate;
- render off-screen at a chosen resolution;
- reproduce seeded effects;
- write image sequences;
- exclude interactive effects or substitute deterministic modes.

Video encoding itself may remain an external-tool concern initially.
