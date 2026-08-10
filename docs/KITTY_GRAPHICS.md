# Kitty graphics protocol transfer and cache

Kiwi implements a deliberately narrow M7 subset of the Kitty graphics
protocol: a direct inline PNG can be transferred through APC-G, decoded into a
bounded CPU RGBA cache, placed over explicit terminal cells, and composed by a
renderer-owned WGPU texture cache.

## Framing and accepted subset

The parser recognizes Kitty's `ESC _ G control ; payload ESC \\` APC framing
(and its C1 APC/ST equivalent). The parser accepts at most 4,096 payload bytes
per APC. It emits an APC action only when the APC starts with `G`; other APC
data is consumed as unsupported control data.

Controls are ASCII, lowercase one-character `key=value` pairs, comma-separated,
with no duplicate or unknown keys. The only accepted actions are:

| Action | Required fields | Effect |
| --- | --- | --- |
| `a=t` | `i`, `s`, `v`, `f=100`, `t=d` | Transfer an inline PNG and cache its decoded RGBA bytes after final validation. |
| `a=q` | the same transfer fields | Validate and decode without caching; reply `OK` or a bounded error code. |
| `a=p` | `i`, `p`, `c`, `r`, `C=1`; optional `z` | Place a stored image in a stationary explicit cell rectangle. |
| `a=d` | `d=a`, or `d=i`/`d=I` with `i`; optional `p` for `d=i`/`d=I` | Clear visible placements, soft-delete placements, or delete image data and placements. |

`m=1` starts or continues one transfer; its next graphics action must contain
only `m=0` or `m=1`. Image IDs are non-zero unsigned 32-bit integers. Kiwi
accepts only PNG (`f=100`) sent directly (`t=d`). Placement requires a non-zero
image and placement ID, explicit positive `c`/`r`, and `C=1`, which selects the
documented no-cursor-movement policy. It may specify a signed 32-bit `z` index.
`a=T`, inferred dimensions, default cursor movement, source rectangles, pixel
offsets, relative/virtual placements, raw RGB/RGBA, zlib compression,
filesystem/shared-memory/file-descriptor media, animation, Unicode placeholders,
and unlisted controls are rejected.

## Bounds and validation order

The default limits are 4,096 APC bytes, 1 MiB encoded transfer data, 256
transfer chunks, one in-flight transfer, 64 image IDs, dimensions from 1 to
8,192 pixels, 16 MiB pixels per image, 64 MiB decoded RGBA per image, 64 MiB
total CPU cache, and 64 MiB accounted GPU cache. All limits are constructor
options for focused tests; production uses these defaults.

Kiwi parses and bounds controls before retaining transfer bytes. It validates
the strict Base64 shape, PNG signature, `IHDR` dimensions, declared dimensions,
pixel count, and RGBA byte count before allocating the RGBA buffer. libpng's
simplified in-memory read API then decodes only into that pre-sized buffer.
Malformed or failed commands clear their in-flight transfer and do not alter
terminal cells, cursor, scrollback, or an existing cached image.

While a transfer is incomplete, its bounded Base64 chunks are terminal-model
data. They are concatenated only on the final chunk, decoded, then discarded.
The retained image record owns only its decoded RGBA allocation and metadata;
it never retains the source payload.

## Placement lifecycle

`terminal/kitty_placements.lua` stores at most 256 placements, each spanning at
most 256 terminal rows. A placement is uniquely keyed by `{image_id,
placement_id}`; a new command with the same pair replaces its prior cell
anchors. It records the current screen scope, starting column, cell width,
z-index, and the stable line IDs of the covered rows. Viewport descriptors map
those line IDs back to current rows and sort by z-index, image ID, and placement
ID. This keeps placement state independent of pixels and rendering.

Full-screen primary scrolling moves anchors into scrollback with their text.
History navigation maps the same anchors back into the viewport. When a
scrollback row is evicted, a margin scroll discards a row, or resize removes a
row, that row reference is clipped; the placement is released only when no row
references remain. A narrower resize clips the cell width or releases an anchor
that no longer intersects the grid. `CSI 2 J` clears visible placement anchors;
other erase commands leave graphics unchanged. Entering a fresh `1049`
alternate screen clears alternate placements, while ordinary primary/alternate
switching keeps each scope separate. A terminal reset clears all placements and
cached image data.

`a=d,d=a` clears visible placement anchors in the active viewport. `a=d,d=i`
removes every matching placement (or the exact matching `p`) while retaining the
image cache; `d=I` additionally releases the decoded image and creates any
needed renderer GPU-release work. Unknown image placement replies with a
bounded `ENOENT:unknown-image`; invalid selected controls reply with
`EINVAL:<reason>`.

## CPU, GPU, and composition ownership

`terminal/kitty_graphics.lua` owns CPU decoded allocations. The cache uses a
monotonic-use LRU policy, breaking ties by lower image ID, for deterministic
replacement when the image-count or CPU-byte bound would be exceeded. Replacing
an ID releases its prior record before the replacement becomes visible.

The terminal model does not own a WGPU texture or any other native handle. The
renderer obtains a stable `{ id, generation, width, height, bytes, pixels }`
upload descriptor, reserves logical GPU bytes, then creates and owns the
texture, view, and bind group through the renderer resource registry. A
generation mismatch, cache eviction, deletion, reset, renderer recreation, or
placement leaving the viewport releases the native objects and logical byte
accounting together. GPU cache eviction uses the same deterministic ordering
and returns release descriptors for the renderer to destroy. This keeps
terminal snapshots, diagnostics, replay, scrollback, and extension resources
free of pixels and native handles.

`terminal.kitty_images` is a typed, plain-data renderer resource. It reports
bounded counts for visible instances, under/over layers, resident textures, and
uploads, plus at most 256 visible placement summaries. A summary contains its
image/placement IDs, cell span, first/last visible row, visible-row count,
z-index, and layer; it contains no pixel pointer or native object. The renderer
uploads one bounded storage-buffer instance per visible anchored row, using that
row's source-row index to sample its vertical slice of the image. It does not
mark terminal cells or text dirty for placement-only changes.

Composition order is fixed:

```text
background -> negative-z images -> selection -> search -> command separators
-> glyphs -> zero/positive-z images -> cursor
```

Thus negative z-index images remain behind text and selection, zero or positive
z-index images can cover glyphs, and the cursor remains visible above both.
Within either image layer, terminal placement order (z-index, image ID,
placement ID) is retained. Arbitrary transforms, clipping shapes, source
rectangles, image editing, animation, and an unbounded texture cache remain out
of scope.

The currently exposed model view/snapshot contains only image IDs, dimensions,
byte totals, generation numbers, cache state, configured limits, and counters.
It excludes Base64, decoded bytes, pixel pointers, source paths, shared-memory
names, file descriptors, and native GPU handles.

## Failures, responses, and fixture coverage

Failures record a fixed bounded reason such as `encoded-limit`,
`invalid-base64`, `png-header`, `png-dimensions`, `png-decode`, or
`cpu-cache-limit`. They are surfaced in the graphics cache counters and F4
diagnostics without logging protocol data. Ordinary transfers do not emit a
reply. A valid `a=q` responds `ESC _ Gi=<id>;OK ESC \\`; a failed query returns
the same framing with a bounded `ERR:<reason>` code.

`src/tests/fixtures/vt/kitty_graphics.lua`,
`src/tests/fixtures/vt/kitty_graphics_actions.lua`, and
`src/tests/fixtures/vt/kitty_graphics_composition.lua` use one reviewable 1×1
PNG Base64 literal. Together they cover transfer, query, placement, visible
negative/positive z composition input, clear, soft delete, and hard delete.
`src/tests/fixtures/replay/kitty-placement.jsonl` verifies replay. Focused tests
cover complete and chunked transfers, every parser split boundary, malformed and
over-limit input, stable `encoded-limit` and `png-decode` diagnostics, query
behavior, deterministic CPU/GPU accounting eviction, placement
replacement/z-order, viewport/history movement, alternate screen/reset/clear/
delete behavior, resize clipping, image-pass ordering, per-row source slicing,
offscreen texture release, and cleanup.

Run `make kitty-graphics-smoke` in a graphical session to launch the same
self-contained direct-PNG client with timestamp instrumentation. On an adapter
with timestamp-query support it reports both `terminal/kitty_images_under` and
`terminal/kitty_images_over`; then run `make conformance-evidence` to
record/replay the stream alongside the other native conformance probes. The
supported direct-PNG stream is intentionally not evidence for arbitrary
third-party Kitty client compatibility.

## Sources

- [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
- [Kitty minimal chunked example](https://sw.kovidgoyal.net/kitty/graphics-protocol/#a-minimal-example)
- [libpng simplified API](https://www.libpng.org/pub/png/libpng-manual.html)
