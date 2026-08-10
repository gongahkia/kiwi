# Renderer pass API v1

`kiwi.renderer.pass_api` is the small, versioned registration surface for a
trusted local Lua render pass. It is not an extension discovery, installer, or
sandbox. The host passes registration functions explicitly when it constructs
`Renderer`; optional extension configuration and containment are separate
work.

The maintained runnable example is
[`src/kiwi/renderer/samples/damage_observer.lua`](../src/kiwi/renderer/samples/damage_observer.lua).
It reads only `terminal.damage` and `frame.timing`, owns no GPU state, and
requests one 250 ms follow-up deadline only on a frame with terminal damage.
The subsequent idle frame does not request another deadline, so it cannot make
an idle terminal redraw continuously.

Run it from a built checkout with:

```sh
KIWI_RENDER_EXTENSIONS=kiwi.renderer.samples.damage_observer \
  KIWI_PASS_METRICS=1 KIWI_MAX_FRAMES=60 \
  make run ARGS='-- /usr/bin/printf "sample extension\n"'
KIWI_RENDER_EXTENSIONS=kiwi.renderer.samples.damage_observer \
  make run ARGS='--no-extensions -- /usr/bin/printf "safe mode\n"'
make check
```

The first command loads the sample; the second proves safe mode bypasses the
same configured module before it is required. The sample's deterministic
contract is exercised by `test_extension_sample.lua`; it is a semantic
observer, not a debug overlay, because API v1 has no drawing or allocation
capability.

`api_version` must be exactly `PassApi.version` (currently `1`). `extension`
and `name` are lowercase identifiers using letters, digits, `_`, and `-`; Kiwi
forms the stable pass identity `extension/<extension>/<name>`. A declaration
needs integer `order`, `reads`, `writes`, `after`, and an `encode` callback.
`initialize`, `resize`, and `shutdown` are optional. All declarations are
validated before the renderer's pass registry becomes active; ordering then
uses the same deterministic dependency graph as the built-ins.

## Advisory budgets

A declaration may include a `budget` table with one or more of `cpu_ms`,
`gpu_ticks`, `allocation_bytes`, and `cadence_hz`, plus optional positive
integer `window` from 1 through 120 (default 30). CPU measures prepare plus encode CPU time.
GPU ticks are evaluated only when asynchronous timestamp samples arrive; they
are not converted to milliseconds. Cadence is the observed maximum callback
rate in hertz. The inspector and `renderer.diagnostics.pass_budgets` expose
the rolling average, latest value, limit, sample count, and structured
over-budget warnings `{ pass, dimension, frame, sample, average, limit,
window }`.

The callback context's plain-data `pass.budget` preserves declared metadata;
`context.budget` reports its latest advisory status. An extension should make
optional work cheaper or request a longer animation delay after an
`over-budget` status. It must not change terminal semantics, assume an
unavailable GPU measurement is zero, or expect Kiwi to throttle/disable it.
API v1 exposes no extension GPU allocation capability, so allocation
accounting reports unavailable rather than guessing memory use.

Callbacks receive fresh plain-data context tables: API version, stable pass
metadata, phase, and cloned semantic resource descriptors. `resize` also
receives previous/current viewport descriptors. v1 never supplies a renderer,
command encoder, native WGPU handle, buffer, texture, pipeline, or shader
module. Reads are limited to ABI-v1 read resources and writes to
`surface.color`; a pass cannot retain or destroy Kiwi-owned resources.

The read-only `terminal.cursor` descriptor carries `column`, `row`, `visible`,
the canonical DECSCUSR `style` (1 through 6), named `shape`
(`block`, `underline`, or `bar`), and `blink`. These are presentation hints
from terminal state, not permission to schedule a redraw or access a native
cursor resource.

The read-only `terminal.selection` descriptor carries `active`, normalized
viewport-relative `start_column`, `start_row`, `finish_column`, and
`finish_row` gaps, plus normalized `color` channels. It contains no selected
text, row IDs, clipboard data, or native buffers. An inactive descriptor has
zero endpoints; coordinates may extend beyond the viewport when an active
range is clipped by the visible grid.

The read-only `terminal.search` descriptor carries `status`, `match_count`,
`current_index`, a current viewport-relative range, normalized `color`, and a
bounded `visible_matches` map. It contains neither the query nor terminal
text. An inactive or stale descriptor has no active range; extensions must not
infer a retained match from omitted data.

The read-only `terminal.hyperlinks` descriptor carries only `active`, normalized
underline `color`, and bounded `visible_cells`. It excludes URI targets,
opaque link IDs, visible text, input state, and native opener handles. An
inactive descriptor has zero visible cells and transparent color.

This API deliberately supports observation and semantic lifecycle integration,
not arbitrary drawing. Future controlled rendering capabilities require their
own versioned ownership and budget contract.

`context.request_animation(delay_seconds)` is the only scheduling capability.
It coalesces an extension redraw deadline and clamps its cadence to the
renderer policy; it does not create an unbounded timer or background loop.
Call it only for a finite state transition and omit it on the resulting idle
frame, as the maintained sample does.

## Discovery and containment

Kiwi discovers no extensions by default and has no built-in network installer. A live
session can opt into trusted local modules with
`KIWI_RENDER_EXTENSIONS=module.one,module.two`; each module must return a
registration function or `{ register = function }`. `--no-extensions` skips
that list before any module is loaded.

Each configured registration runs in a fresh API collector and is preflighted
with the complete built-in graph plus previously accepted extensions. A
registration that raises, declares an invalid pass, exceeds the 32-pass
extension limit, or creates an invalid graph is discarded as a whole. It
cannot leave partially registered optional passes in the built-in graph.

The extension diagnostic snapshot is available through
`renderer.diagnostics.extensions` and the regular metrics snapshot. It is
plain data with `enabled`, a `disabled` pass-name map, and bounded diagnostic
records `{ extension, pass, phase, message }`; history holds at most 32
records and each message is capped at 4,096 bytes.

If an optional pass callback fails during initialization, encoding, resize, or
shutdown, Kiwi records its extension and pass identity, disables that pass for
the remaining renderer lifetime, and continues the core pass lifecycle where
the renderer can safely do so. A built-in pass failure remains fatal. This is
containment for trusted local code, not a Lua or native-code sandbox.

## Hard limits

| Limit | Default | Configuration | Failure behavior |
| --- | --- | --- | --- |
| Optional passes | 32 passes | `KIWI_EXTENSION_MAX_PASSES` or `Renderer.new` `extension_pass_limit` | Reject the whole registration before it joins the graph. |
| Optional animation cadence | 60 Hz, minimum delay 1/60 second | `KIWI_EXTENSION_MAX_ANIMATION_HZ` (1/60 through 60) or `extension_animation_hz` | Reject the request before scheduling a redraw. |
| Callback failures | 1 per pass | Fixed containment policy | Disable the optional pass for this renderer lifetime. |
| Diagnostic history | 32 records × 4,096 bytes | `extension_diagnostic_limit` and `extension_diagnostic_message_limit` | Drop the oldest record and truncate an oversized message. |
| Extension-owned buffers, textures, texture dimension, GPU memory | 0 | Unsupported in API v1 | No allocation capability is exposed. GPU-memory accounting is reported as unavailable. |
| Extension shader failures | 0 | Unsupported in API v1 | No shader-module capability is exposed. |

Cap diagnostics add `requested { kind, value }` and `limit { kind, value }`
to the normal extension/pass/phase/message record. The state is bounded by the
pass and diagnostic limits. Kiwi's pinned native binding does not expose a
GPU-memory budget or usage query, so the v1 diagnostic explicitly reports
that accounting as unavailable rather than estimating it or stalling a frame.
