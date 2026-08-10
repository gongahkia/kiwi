# ADR 0016: versioned semantic render-pass and resource ABI

## Context

Kiwi M2.5 has three renderer-owned passes: `terminal/background`,
`terminal/glyph`, and `terminal/cursor`. `Renderer` owns their pipelines,
buffers, bind groups, shader module, atlas, and command encoding directly.
`State` and `Layout` already produce terminal cells, shaped glyphs, cursor
state, logical/text damage, and viewport dimensions, but no contract says how
a pass may consume those values or how a future local extension is contained.

M3 needs a shared lifecycle before pass registration, graph dependencies,
shader loading, or extensions can be implemented. That lifecycle must retain
the terminal-model/renderer boundary and cannot make LuaJIT FFI pointers part
of an extension interface.

## Decision

Define the initial contract as **Kiwi semantic render ABI v1**. An
implementation exposes `abi_version = 1` and rejects a registration that does
not request exactly that version. A later incompatible change to a required
field, resource meaning, lifecycle stage, or capability boundary receives a
new major ABI version. Additive optional fields may be introduced only when
their absence has a specified default and v1 passes retain their behavior.

### Pass identity and lifecycle

Each pass has a unique stable name, a deterministic ordering key, declared
semantic resource reads, declared presentation-target writes, and these
lifecycle stages:

```text
registered -> validated -> initialized -> ready -> encoding* -> shutdown
```

`encoding` repeats once per rendered frame while the pass is `ready`.
Registration and validation occur before a pass changes the active renderer.
Initialization can acquire only resources allocated through Kiwi-owned typed
descriptors. A resize, surface reconfiguration, font/content-scale rebuild,
or renderer recreation makes old resource capabilities stale before the next
pass initialization. Every initialized pass receives exactly one `shutdown`,
in reverse initialized order, including after a later initialization failure.

No lifecycle callback may mutate terminal state, parser state, text shaping,
or terminal-width policy. Passes describe presentation; they do not decide
what a terminal cell means.

Current built-ins map into v1 without adding a new visual feature:

| Pass | Required reads | Presentation write | Existing order |
| --- | --- | --- | ---: |
| `terminal/background` | `terminal.cells`, `frame.viewport` | `surface.color` | 10 |
| `terminal/glyph` | `text.shaped_glyphs`, `text.alpha_atlas`, `frame.viewport` | `surface.color` | 20 |
| `terminal/cursor` | `terminal.cursor`, `frame.viewport` | `surface.color` | 30 |

Each built-in also receives `frame.timing` and `terminal.damage` as declared
read-only frame inputs. The matching render-pass attachment load behavior is
part of each pass implementation: background clears and glyph/cursor load the
prior colour result. The shared lifecycle must preserve that behavior.

### v1 resources and validity

The v1 registry has only the existing resource vocabulary below. A resource
capability is read-only unless marked as Kiwi-owned output. It includes a
generation and is valid only for its declaring renderer generation and
lifecycle callback. Resolving an unknown, unavailable, or stale capability is
an error at the nearest registration/lifecycle boundary.

| Resource | Producer and meaning | Availability |
| --- | --- | --- |
| `terminal.cells` | terminal grid cell attributes and grid dimensions | read-only; current visible model snapshot |
| `text.shaped_glyphs` | HarfBuzz/FreeType-derived visible glyph records | read-only; may be empty when text has no drawable glyphs |
| `terminal.cursor` | column, row, and visibility after terminal/history policy | read-only; always present |
| `terminal.damage` | coalesced logical-damage summary/ranges for the current update | read-only; may be empty |
| `frame.viewport` | logical columns/rows, drawable pixels, and content scale | read-only; always present for a drawable frame |
| `frame.timing` | monotonic frame time and non-negative frame delta | read-only; always present; timing does not imply redraw permission |
| `text.alpha_atlas` | Kiwi-owned current grayscale atlas description/content | read-only; unavailable only when the text system is unavailable during rebuild |
| `surface.color` | configured frame presentation target | Kiwi-owned output; passes may declare a write but never own, retain, or destroy it |

`terminal.cells`, `text.shaped_glyphs`, and `text.alpha_atlas` expose their
semantic meaning and validated descriptor metadata, not the renderer's FFI
arrays, `WGPUBuffer`, `WGPUTexture`, bind group, pipeline, queue, device,
surface, command encoder, or shader-module pointers. A future controlled
encoder or typed allocation capability may use those private handles behind
the boundary, but it must not reveal them to Lua passes. A pass cannot retain
a frame resource for a later frame.

Selection, hyperlinks, command regions, images, clipboard data, shell data,
and arbitrary graphics textures are intentionally absent from v1. They need
their own semantic producer, ownership policy, and versioned addition.

### Invalidation, scheduling, and failure behavior

The registry reports reasons rather than allowing a pass to inspect or clear
terminal damage. Initial v1 reasons are `content`, `cursor`, `viewport`,
`scale`, `atlas`, and `time`. `content` corresponds to the existing text
damage/layout update; `cursor` corresponds to logical presentation damage that
does not require shaping; `viewport` and `scale` cover current resize/rebuild
paths; `atlas` covers a changed glyph-cache generation. `time` is an observed
frame value only. Requesting future animation/redraw scheduling is deliberately
outside v1 and is specified by the bounded scheduler work in #104 and #158.

Validation, initialization, encoding, and shutdown failures must include the
pass name, lifecycle stage, and requested resource or descriptor. The pass
registry keeps only bounded diagnostic summaries; it does not retain shader
source, terminal contents, or an unbounded traceback history. A failed
activation cannot leave a partially initialized pass active. The exact policy
for disabling a trusted optional extension while retaining built-ins is
implemented by #100 and #158; this ABI requires enough identity and lifecycle
information to make that policy observable.

### Ownership and compatibility boundary

Kiwi owns terminal semantics, shaped-text generation, all native wgpu objects,
resource accounting, renderer-generation changes, and final destruction.
Passes may declare only capabilities documented by their ABI version. They
cannot create a parallel terminal model, call wgpu through a supplied native
pointer, or take ownership of a resource created by Kiwi. Trusted local Lua is
not a hostile-code sandbox; the boundary prevents accidental lifetime and
ownership violations, while cap and containment work supplies explicit bounds.

## Consequences

The fixed list in `renderer/passes.lua` becomes a migration target rather than
an extension API. #93 implements typed capabilities and generation checks;
#94 implements the deterministic lifecycle and built-in migration; #95 adds
dependency ordering; #99 adds shader source/module diagnostics; #100 adds
optional-extension containment; #102/#109 add per-pass measurements and
budgets; #103 exposes a versioned Lua registration surface; and #104/#158 add
bounded invalidation, animation, and allocation policy. Those changes must
preserve the three built-in pass outputs before accepting extensions.

Focused tests should cover duplicate pass identity, invalid ABI version,
unknown/stale resources after renderer recreation, declared resource access,
deterministic built-in order, reverse cleanup after initialization failure,
and diagnostics bounded by repeated failures. Native smoke must continue to
exercise the unchanged background/glyph/cursor sequence. `make check` remains
the required broad validation once implementation begins.

