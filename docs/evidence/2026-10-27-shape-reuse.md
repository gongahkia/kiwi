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
