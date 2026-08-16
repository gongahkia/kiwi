# Kitty graphics protocol transfer and cache

Kiwi implements a deliberately narrow M7 subset of the Kitty graphics
protocol: direct inline PNG, APNG, and GIF data can be transferred through
APC-G, decoded into a bounded CPU RGBA cache, placed over explicit terminal
cells, and composed by a renderer-owned WGPU texture cache.

## Framing and accepted subset

The parser recognizes Kitty's `ESC _ G control ; payload ESC \\` APC framing
(and its C1 APC/ST equivalent). The parser accepts at most 4,096 payload bytes
per APC. It emits an APC action only when the APC starts with `G`; other APC
data is consumed as unsupported control data.

Controls are ASCII, lowercase one-character `key=value` pairs, comma-separated,
with no duplicate or unknown keys. The only accepted actions are:

| Action | Required fields | Effect |
| --- | --- | --- |
| `a=t` | `i`, `s`, `v`, `f=100`, `t=d` | Transfer inline PNG, APNG, or GIF bytes and cache bounded decoded RGBA frames after final validation. |
| `a=q` | the same transfer fields | Validate and decode without caching; reply `OK` or a bounded error code. |
| `a=p` | `i`, `p`, `c`, `r`, `C=1`; optional `z` | Place a stored image in a stationary explicit cell rectangle. |
| `a=d` | `d=a`, or `d=i`/`d=I` with `i`; optional `p` for `d=i`/`d=I` | Clear visible placements, soft-delete placements, or delete image data and placements. |

`m=1` starts or continues one transfer; its next graphics action must contain
only `m=0` or `m=1`. Image IDs are non-zero unsigned 32-bit integers. Kiwi
accepts PNG, APNG, or GIF bytes sent directly with `f=100` and `t=d`. This is a
Kiwi extension of the otherwise PNG-labelled direct transfer field, not a claim
that unmodified third-party Kitty clients negotiate these formats. Placement
requires a non-zero image and placement ID, explicit positive `c`/`r`, and
`C=1`, which selects the documented no-cursor-movement policy. It may specify a
signed 32-bit `z` index. `a=T`, inferred dimensions, default cursor movement,
source rectangles, pixel offsets, relative/virtual placements, raw RGB/RGBA,
zlib compression, filesystem/shared-memory/file-descriptor media, Unicode
placeholders, and unlisted controls are rejected.

## Explicit HTTPS URL helper

Kiwi does not fetch image URLs while parsing terminal output. The optional
`kiwi-image` client is an explicit user action that downloads one HTTPS URL
with `curl`, validates it as a bounded PNG/APNG or GIF, then emits Kiwi's
direct-image APC-G stream. It accepts HTTPS redirects only, uses connection and
total timeouts, limits downloaded image data to 720 KiB, validates the PNG/APNG
IHDR or GIF logical-screen dimensions, and keeps the encoded transfer below
Kiwi's 1 MiB limit. It does not accept `http`, `file`, other non-HTTPS
protocols, WebP, or video.

From a source checkout, run this inside a Kiwi shell:

```sh
./script/kiwi-image https://images.example/kiwi.gif
```

The release artifact and Nix package install the same helper as `kiwi-image`.
Use `--file path.png`, `--file path.apng`, or `--file path.gif` for a local
direct-image transfer, `--columns N` and
`--rows N` to set the terminal-cell rectangle, and `--z N` to choose its
composition layer. By default, the helper waits for and consumes the placement
acknowledgement, then starts subsequent output at the first column below the
image rectangle. This keeps the shell prompt and ordinary terminal text out of
the placed image. `--no-cursor-advance` retains the stationary placement used
by composition fixtures.

## Bounds and validation order

The default limits are 4,096 APC bytes, 1 MiB encoded transfer data, 256
transfer chunks, one in-flight transfer, 64 image IDs, dimensions from 1 to
8,192 pixels, 16 MiB pixels per canvas, 64 MiB decoded RGBA per static image,
256 retained animation frames, 32 MiB retained composited RGBA bytes per
animation, 64 MiB total CPU cache, and 64 MiB accounted GPU cache. The
animation-byte cap derives from a lower configured CPU cap, so focused tiny-cache
tests remain valid. All limits are constructor options; production uses these
defaults.

Kiwi parses and bounds controls before retaining transfer bytes. It validates
the strict Base64 shape, detected-media header, declared dimensions, pixel
count, and RGBA byte count before allocating the first RGBA buffer. Static PNG
uses libpng's simplified in-memory read API. APNG validates chunk bounds, CRCs,
sequence numbers, frame controls, blend/disposal operations, and declared frame
count before reconstructing and compositing each retained frame through libpng.
GIF uses giflib to decode indexed frames, including local/global palettes,
transparency, interlace, disposal, and loop metadata. Malformed or failed
commands clear their in-flight transfer and do not alter terminal cells, cursor,
scrollback, or an existing cached image.

While a transfer is incomplete, its bounded Base64 chunks are terminal-model
data. They are concatenated only on the final chunk, decoded, then discarded.
The retained image record owns only static RGBA pixels or bounded composited
animation frames plus metadata; it never retains the source payload.

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
scrollback row is evicted, a margin scroll discards a row, or a fixed-grid
resize removes a row, that row reference is clipped; the placement is released
only when no row references remain. A primary-screen column resize instead
reflows text and releases every primary placement anchor before rebuilding the
grid: the placement's fixed rectangle cannot be translated safely through text
reflow. The decoded image cache remains available for a later placement. An
alternate-screen or same-column resize clips the cell width or releases an
anchor that no longer intersects the grid. `CSI 2 J` clears visible placement anchors;
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
renderer obtains a stable `{ id, generation, width, height, frame_bytes,
frame_revision, pixels }` upload descriptor, reserves logical GPU bytes for one
canvas, then creates and owns the texture, view, and bind group through the
renderer resource registry. An animated frame rewrite updates that resident
texture in place; it does not retain a GPU texture per frame. A generation
mismatch, cache eviction, deletion, reset, renderer recreation, or placement
leaving the viewport releases the native objects and logical byte accounting
together. GPU cache eviction uses the same deterministic ordering and returns
release descriptors for the renderer to destroy. This keeps terminal snapshots,
diagnostics, replay, scrollback, and extension resources free of pixels and
native handles.

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
placement ID) is retained. Animated images schedule their next bounded frame
deadline only while they have a visible placement; GIF/APNG playback pauses
while hidden and does not allocate another texture. Arbitrary transforms,
clipping shapes, source rectangles, image editing, video, and an unbounded
texture cache remain out of scope.

The currently exposed model view/snapshot contains only image IDs, dimensions,
byte totals, generation numbers, cache state, configured limits, and counters.
It excludes Base64, decoded bytes, pixel pointers, source paths, shared-memory
names, file descriptors, and native GPU handles.

## Failures, responses, and fixture coverage

Failures record a fixed bounded reason such as `encoded-limit`,
`invalid-base64`, `png-header`, `png-dimensions`, `png-decode`, `gif-decode`,
`apng-frame-control`, `animation-frame-limit`, `animation-byte-limit`, or
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
over-limit input, static PNG diagnostics, GIF/APNG frame decoding and playback,
GIF background disposal, animation frame/byte limits, frame-texture rewrites,
deterministic CPU/GPU accounting eviction, placement replacement/z-order,
viewport/history movement, alternate screen/reset/clear/delete behavior, resize
clipping, image-pass ordering, per-row source slicing, offscreen texture release,
and cleanup.

Run `make kitty-graphics-smoke` in a graphical session for the static PNG
composition client, or `make kitty-animation-smoke` for the self-contained
GIF/APNG playback client. On an adapter with timestamp-query support both report their
Kitty image pass samples; then run `make conformance-evidence` to record/replay
the static stream alongside the other native conformance probes. The supported
direct-image stream is intentionally not evidence for arbitrary third-party
Kitty client compatibility.

## Sources

- [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
- [Kitty minimal chunked example](https://sw.kovidgoyal.net/kitty/graphics-protocol/#a-minimal-example)
- [giflib](https://sourceforge.net/projects/giflib/)
- [libpng simplified API](https://www.libpng.org/pub/png/libpng-manual.html)
