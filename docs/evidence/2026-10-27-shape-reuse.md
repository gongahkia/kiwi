# Bounded shaping reuse, 2026-10-27

A damaged text row previously called HarfBuzz for every run, even if another row
had just shaped exactly the same text with the same font. A local Intel macOS
probe retained 10,000 history rows, warmed twenty redraws of an 80×24 grid, timed
200 redraws with normal garbage collection, then measured transient allocation
across twenty redraws with collection stopped. A separate twenty redraws counted
calls to `Face:shape`; that wrapper was absent from the timed/allocation phases.
The [probe source](2026-10-27-shape-reuse-probe.lua) uses the styled Unicode line
from the native interactive workload, real font resolution and HarfBuzz, without
GPU rendering, PTY traffic or accessibility projection. Its repetitions request
full text damage but do not scroll or parse additional output during measurement.

| Observation | Before (`319d582`) | With cache (`8377c6c` code) |
| --- | ---: | ---: |
| 200 redraws, process CPU ms | 818.341 | 618.638 |
| Twenty redraws, temporary Lua allocation KiB | 27,893.828 | 22,540.398 |
| Twenty warmed redraws, `Face:shape` calls | 4,140 | 0 |
| Distinct face/text combinations among those calls | 9 | 0 |

These are single local observations with uncontrolled host load. They show
eliminated repeated shaping and lower temporary allocation in this workload,
not a repeatable latency improvement or native full-history qualification.

The cache is private to each layout and retains at most 256 entries, 32 KiB of
UTF-8 keys and 4,096 shaped glyph records. Individual runs exceeding 1,024 text
bytes or 256 glyphs are shaped in full and bypass retention. FIFO eviction drops
references without mutating arrays. Keys use actual face object identity and
exact UTF-8 text. Changes to ligatures, contextual alternates, script or language
clear entries; font-system replacement, text-generation changes and layout
teardown also clear them. The layout borrows cached font-relative results and
builds fresh screen positions, colours, atlas references and decoration records.
Old returned frames are not mutated by cache reuse.

`runs_reshaped` and `codepoints_shaped` count actual shaping work. `runs_built`
and `visible_runs` continue to count all layout runs, including reused shapes.
`run_cache_hits` reports raw run reuse in layout statistics, exposed as
`run_shape_cache_hits` in frame diagnostics. Existing `shape_cache_hits` frame
metrics still count unchanged **rows**, preserving their previous meaning.

Five native-independent tests cover exact keys, same numeric ID/different face
objects, every shaping option, mutated option tables, FIFO wraparound and all
three total limits, face-reference cleanup, oversized runs and warmed allocation.
A real-font differential test compares every rendered glyph field with uncached
shaping across colours, scrolling, combining/wide text, shaping options, fallback
invalidation, resize, alternate-screen switches and font replacement. It also
checks that previously returned frame records remain unchanged.

The three targeted suites passed all 35 tests with the JIT enabled and disabled.
`make check` passed on Intel macOS: 696 Lua tests across 134 suites, 19 PTY tests,
readiness/benchmark/report fixtures, regex oracle, terminfo, CLI and syntax gates.
Bash, Zsh, fish and Nushell were all required via `KIWI_REQUIRE_SHELLS`; no shell
integration was skipped. The Linux-only GLib fixture was skipped on macOS.

Reproduce the current probe from the repository root:

```sh
LUA_PATH='src/?.lua;src/?/init.lua;;' luajit docs/evidence/2026-10-27-shape-reuse-probe.lua
```

For the before observation, the same probe used the pre-change `layout.lua`
through a temporary leading `LUA_PATH` directory; all other code was unchanged.
Native graphical follow-up remains required with the existing latency/memory
gates and without profiling callbacks or disabled collection.

## Ordinary native follow-up: latency passes, heap growth fails

The [600-second GTK/WGPU trial](2026-10-27-history-linux-gtk-shape-cache-600.json)
ran at clean `73f18bb` in the owned Ubuntu 24.04 container, two CPUs / 4 GiB,
private Xvfb and Mesa llvmpipe Vulkan. It used the ordinary launcher, normal
collection and no profiler or trace callbacks. No other Kiwi build, test or
benchmark ran concurrently; unrelated workstation load was uncontrolled.
The native grid was 72×22 with 10,000 retained history rows.

All 120 measured inputs plus six warmup inputs completed. Post-warmup resource
observations span 623.93 seconds. Callback-to-present-return p95 was 267.73 ms,
p99 332.54 ms and maximum 485.93 ms, below the unchanged two-second ceiling.
Startup to child-ready presentation was 1,293.94 ms. The slowest input reached
the PTY in 2.33 ms; five 4 KiB reads used 151.83 ms parsing, 214.89 ms preparing
frames and 92.52 ms rendering (wall times). History evicted 2,416,351 rows while
retaining exactly 10,000. Final JIT inspection found 846 traces and 1,496,787
emitted machine-code bytes.

The **overall trial failed** its existing Lua heap-growth gate. Last-quarter
minus first-quarter median heap was 54,633.08 KiB (53.35 MiB), exceeding 16 MiB.
Process RSS median growth was 40,856 KiB (39.90 MiB), below 64 MiB; sampled peak
RSS was 684,776 KiB (668.73 MiB), below 1 GiB. Process CPU averaged 168.70%.
The report preserves `status: failed`; no gate or runtime GC policy changed.

Raw heap samples repeatedly rise and fall, ranging from approximately 159 to
358 MiB over the run; the final observation is 166.54 MiB. This is consistent
with collection-cycle effects on the median statistic, but does not itself
measure live retained objects or prove absence of a leak. The next investigation
must separate retained history/storage from transient allocation and collection
phase, while retaining the raw evidence and resource limits. A single passing
latency trial on this shared software-rendering runner also does not establish
repeatable responsiveness or a causal before/after speedup.

Linux's three targeted shaping/font suites passed all 35 tests before this run.

## Component retention diagnostic

A separate [Linux parser/layout probe](2026-10-27-shape-retention-probe.lua)
used the same styled line, a 72×22 state, 10,000 history capacity, real fonts
and one layout update per 32 input lines. It ran after the native trial ended,
at the same container code revision. Normal collection remained enabled inside
intervals; explicit complete collections occurred only at the four diagnostic
checkpoints. This is intentionally **not** a native latency or soak qualification.

The [raw checkpoint output](2026-10-27-shape-retention-linux.jsonl) records:

| Lines processed | Retained history rows | Heap before collection, KiB | Heap after collection, KiB |
| ---: | ---: | ---: | ---: |
| 10,016 | 9,995 | 160,580.158 | 122,280.975 |
| 20,000 | 10,000 | 293,664.385 | 122,470.006 |
| 40,000 | 10,000 | 246,522.385 | 122,601.881 |
| 80,000 | 10,000 | 148,883.775 | 122,602.451 |

The first checkpoint was five rows short of capacity, so the steady-state
comparison starts at 20,000 lines. Retained heap then grew 132.445 KiB across
60,000 further lines and stabilized between the last two checkpoints. The raw
shape cache held nine entries / 28 glyph records / 49 text bytes throughout.
This narrows the investigation but excludes native GPU resources, the window
controller, accessibility and benchmark state. It does not establish retained
heap stability for the full application. The native trial remains failed.
