# Colour glyph and fallback qualification, 2026-10-26

Implementation commits: `b19f1ce`, `64ddf93`, `e8b783a`, `c51a62e`, `997be04`,
`dab9fb9`, `eb3ad57`, and `e2d9bd8`. Font requirements and CI are committed.
Windows remains explicitly deferred to the user's laptop.

## Deterministic gates

- macOS Intel: `make check test-core` passed 632 full tests and 396 core tests,
  plus PTY/readiness/watchers/process metrics/regex oracle/terminfo/CLI/syntax.
  After adding colour-face reuse, `make test` passed **633 tests / 124 suites**.
- Ubuntu 24.04 x86_64 container: the same full suite passed, including the
  additional face-reuse test. **396 core tests / 66 suites** passed with native
  loading disabled. `gtk-host-check` passed with GL bridge ABI 4 / render model 3.
  An intermediate syntax run found macOS AppleDouble files copied into the
  container during debugging. Those generated files were removed and the syntax
  gate passed; they were never repository source. A later initial test command
  omitted the custom GLFW pkg-config path and correctly rejected system GLFW
  3.3; rerunning with the required GLFW 3.4 environment passed.

New tests cover arbitrary strike sizes, joined emoji, variation selectors,
flags, skin tones, candidate loading failures, reusable colour faces, fallback
column placement, missing-text placeholders, BGRA conversion, alpha-preserving
resampling, stride/size bounds, mixed atlas eviction and native raster failures.

## Native pixel readback

Final execution used the `e2d9bd8` Lua sources and the matching native renderer
changes. The fixture renders a known half-transparent red BGRA bitmap with a
green foreground, a grayscale mask tinted green, concealed colour ink, and real
grinning-face emoji. It derives the emoji's expected opaque colour from the
selected font bitmap, then checks that colour in the framebuffer.

| Host | Half-red pixels | Gray-mask green pixels | Native emoji pixels | Font |
|---|---:|---:|---:|---|
| macOS Intel / Metal / GLFW | 2,300 | 2,254 | 480 | Apple Color Emoji |
| Linux Xvfb / software Vulkan / GLFW | 528 | 552 | 1,008 | Noto Color Emoji |
| Linux Xvfb / software Vulkan / GTK | 528 | 552 | 1,008 | Noto Color Emoji |
| Linux Xvfb / GTK GL | 528 | 552 | 1,008 | Noto Color Emoji |

All four concealed-glyph checks observed zero matching pixels. WGPU's sRGB
surface expects half-red near 188; GTK GL's encoded-colour target expects 128.
GTK GL area lifecycle also passed. The first GL diagnostic sampled GTK's
previously handed-off buffer; sampling inside the actual render callback fixed
the diagnostic. The final gate did not relax its expected colours or thresholds.

Existing underline framebuffer checks also passed after the RGBA conversion:
103,511 independently coloured pixels on macOS and 64,074 on Linux. Linux's
font-cache-saturated URL-hint framebuffer regression passed as well.

Reproduce with `make color-glyph-smoke`; on Linux use a graphical session or
`xvfb-run -a`, and set `KIWI_HOST=gtk` and optionally `KIWI_GTK_PRESENTER=gl`.
Linux needs a usable bitmap colour font (`fonts-noto-color-emoji` in these runs).
CI runs all three Linux presentation configurations and the two macOS jobs.
Configured CI is not evidence that a remote job has executed.

## Bounded stress

Both final runs used 5,000 mixed-text rounds, 5,000 exact-ASCII recovery rounds,
5,000 exact-colour recovery rounds, and 64 font-system lifecycles. The colour
phase cycles 64 emoji through four renditions and deliberately clears the
bounded fallback-decision cache every 32 rounds. It verifies actual glyph IDs,
colour metadata and storage bounds after churn. The test atlas is 256×256 RGBA
(256 KiB), limited to 96 entries; the application default is 1024×1024 (4 MiB).

| Measure | macOS | Linux container |
|---|---:|---:|
| Total process CPU | 23,508 ms | 43,202 ms |
| Colour recovery CPU | 7,313 ms | 8,810 ms |
| Retained atlas entries | 80 / 96 | 50 / 96 |
| Evictions | 9,888 | 9,930 |
| Glyph failures / capacity failures | 0 / 0 | 0 / 0 |
| Loaded faces | 24 / 32 | 12 / 32 |
| Retained Lua heap growth | 4,233 KiB | 1,391 KiB |
| Resident growth | 19,384 KiB | 29,508 KiB |

Both resident deltas are below the 96 MiB stress ceiling. macOS used an Intel
Core i5-8279U; Linux ran in the existing two-CPU/4-GiB qualification container.
The runs were sequential. Different operating systems, fonts and runtimes make
these host results unsuitable as a performance comparison.

Before reusable colour faces, the same macOS workload took 73,597 ms total CPU,
including 62,428 ms in colour recovery. The later run used 23,508 / 7,313 ms.
This single before/after experiment identified repeated Fontconfig matching as
a material avoidable cost. It is not a statistical regression threshold or a
claim about displayed latency. Whole-page RGBA uploads, broad throughput,
startup, idle wakeups and application memory remain separate performance work.

Raw reports:

- [macOS before face reuse](2026-10-26-macos-color-stress-before-face-reuse.json)
- [macOS final](2026-10-26-macos-color-stress.json)
- [Linux final](2026-10-26-linux-color-stress.json)

The macOS reports' dirty flags reflect the pending `docs/TEXT.md` boundary
correction, not uncommitted implementation changes. Linux records its source
archive's `BUILD_REVISION`. An initial Linux stress completed its assertions
but could not write the JSON into a root-owned results directory; the directory
ownership was corrected and the final run above completed and wrote its report.

## Limits

Qualified colour formats are Apple sbix and Noto CBDT/CBLC through FreeType
BGRA output. There is no COLRv1 paint interpreter, OpenType SVG renderer, bidi
implementation, multipage atlas or universal font-coverage guarantee. Saturated
simultaneously pinned working sets can still fall back. Xvfb/software-renderer
results do not qualify Wayland compositors, physical displays, fractional scaling,
monitor transitions, screen readers, IMEs, suspend/resume, or all GPU drivers.
Those remain open in the implementation ledger.
