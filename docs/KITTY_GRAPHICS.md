# Kitty graphics protocol transfer and cache

Kiwi implements a deliberately narrow M7 subset of the Kitty graphics
protocol: a direct inline PNG can be transferred through APC-G, decoded into a
bounded CPU RGBA cache, and offered to a future renderer through an explicit
upload descriptor. It does not yet place or render an image.

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

`m=1` starts or continues one transfer; its next graphics action must contain
only `m=0` or `m=1`. Image IDs are non-zero unsigned 32-bit integers. Kiwi
accepts only PNG (`f=100`) sent directly (`t=d`). `a=T`, placement, deletion,
raw RGB/RGBA, zlib compression, filesystem/shared-memory/file-descriptor
media, animation, Unicode placeholders, and unlisted controls are rejected.
Placement and deletion are reserved for #133.

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

## CPU and GPU ownership

`terminal/kitty_graphics.lua` owns CPU decoded allocations. The cache uses a
monotonic-use LRU policy, breaking ties by lower image ID, for deterministic
replacement when the image-count or CPU-byte bound would be exceeded. Replacing
an ID releases its prior record before the replacement becomes visible.

The terminal model does not own a WGPU texture or any other native handle. A
future renderer obtains a stable `{ id, generation, width, height, bytes,
pixels }` upload descriptor, creates and owns its native object through the
renderer resource registry, then registers logical byte accounting. GPU cache
eviction uses the same deterministic ordering and returns release descriptors
for the renderer to destroy. Reset and CPU eviction likewise enqueue a release
descriptor. This keeps terminal snapshots, diagnostics, replay, scrollback,
and extension resources free of pixels and native handles.

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

`src/tests/fixtures/vt/kitty_graphics.lua` contains a real 1×1 PNG APC-G
fixture. Focused tests cover complete and chunked transfers, every parser split
boundary, malformed and over-limit input, query behavior, deterministic CPU and
GPU accounting eviction, and reset cleanup.

## Sources

- [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
- [Kitty minimal chunked example](https://sw.kovidgoyal.net/kitty/graphics-protocol/#a-minimal-example)
- [libpng simplified API](https://www.libpng.org/pub/png/libpng-manual.html)
