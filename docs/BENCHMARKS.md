# Kiwi M1.5 and M2 benchmarks

M1.5 measures the real LuaJIT terminal pipeline in layers instead of inferring terminal performance from the older synthetic renderer model. The benchmarks are reproducible CPU measurements, not a claim of end-to-end terminal or GPU latency.

```sh
make bench
KIWI_BENCH_ITERATIONS=100 KIWI_BENCH_WARMUP=20 make bench
make bench-burst
KIWI_BURST_10MB=1 make bench-burst
make bench-compare BASELINE=bench/results/baseline.json CANDIDATE=bench/results/candidate.json
```

`make bench` defaults to 50 measured iterations and 10 warm-up iterations. It writes schema-version-3 JSON to `bench/results/<UTC timestamp>.json`. `make bench-burst` uses the real nonblocking PTY and writes a separate `*-burst.json` result. Generated results are intentionally not source-controlled.

## Method and scope

Each measured iteration starts after its parser/state/setup object exists. Inputs and pre-materialized action streams are constructed before timing. CPU samples use `os.clock` process CPU time and report total, mean, p50, p95, and p99. LuaJIT version, enabled JIT features, architecture/kernel, revision/dirty state, CFLAGS value, iteration count, warm-up count, and exact scope are embedded in every result.

The component suite covers these layers:

| Layer | Timed work |
| --- | --- |
| byte/UTF-8 | byte iteration and incremental UTF-8 decoding, including valid multibyte and invalid input |
| parser-only | streaming parser plus observable action-table callback; state is excluded |
| state-only | pre-materialized actions applied to a fresh terminal state and damage tracker |
| parser/state | production direct-print parser sink plus state/damage |
| damage | contiguous and deliberately fragmented interval coalescing, range discovery, and clear |
| packing | the real `Renderer:pack_cell` CPU path with a deterministic atlas stub; GPU calls are excluded |
| real scroll | primary full-screen, large-grid, and margin `State:scroll_up` paths |
| full CPU pipeline | in-memory PTY bytes through parser, state, damage ranges, and `Renderer:pack_cell` |

The full CPU pipeline intentionally excludes PTY syscalls, `wgpuQueueWriteBuffer`, GPU execution, compositor scheduling, and presentation. The packing layer calls the renderer's actual packing method, but the atlas stub makes it a CPU-only test. `make smoke` remains the native presentation correctness check.

Heap fields are diagnostic signals, not allocation totals: retained delta is measured after an explicit collection and peak delta is allocator-sensitive. Peak values include the fresh per-iteration setup needed by the component. Use them to spot growth or runaway retention, not to compare unrelated layers by a few KiB.

The schema retains `legacy_m0_synthetic_results` separately. M0's synthetic scrolling reconstruction and M1.5's row-reference terminal scrolling have different scopes and must not be presented as before/after performance evidence.

## M2 native-text measurements

`make bench-text` is deliberately separate from `make bench`: it defaults to 10 measured iterations and 3 warmups, writes `bench/results/<UTC timestamp>-text.json` with schema version 1, and does not alter the M1.5 schema. It reports each ASCII, combining, CJK, emoji, and mixed workload at these layers:

| Layer | Timed work |
| --- | --- |
| UAX #29 segmentation | decoded code points through EGC segmentation |
| terminal width | segmentation plus the versioned M2 width policy |
| HarfBuzz cold | shaping against a fresh pre-created Fontconfig/FreeType/HarfBuzz/fallback context |
| HarfBuzz/glyph-cache hot | shaping against persistent fallback and prepopulated glyph caches |
| fallback lookup | primary coverage, initial CJK resolution, and cached CJK fallback as independent scopes |
| glyph atlas | glyph-ID rasterize/insert miss, hot hit, and deterministic bounded-capacity rejection |
| row layout cold | first logical-row layout against fresh pre-created state/font/layout objects |
| row layout cached | a static, already-shaped row with cleared logical damage |
| row layout edit | one ASCII, combining, CJK, emoji-width-changing, or full-row edit through reshaping and glyph-instance creation |
| full text pipeline | parser direct-print sink through EGC state, width, shaping, fallback, glyph cache, and Lua glyph instances |

Each JSON result carries the exact scope, input bytes/code points/clusters/runs/glyphs/glyph instances, logical dirty cells, cache/fallback counters, CPU samples, and Lua heap deltas. Object construction occurs before the timed operation, matching the M1.5 methodology; a “cold” operation means a fresh cache/context, not that native library construction time is attributed to shaping. None of these layers measure GPU queue writes, GPU execution, compositor delay, or presentation.

`make bench-text-stress` writes `*-text-stress.json`. It mixes unique glyphs, long combining sequences, CJK, emoji, PUA, bounded negative fallback, CSI edits, resize, and layout in one long-lived system, then repeatedly creates/destroys independent text systems. It reports atlas bytes/entries, face/fallback/shape-cache entries, lifecycle count, heap, and RSS. It checks anchor/continuation invariants, atlas and fallback-cache limits, and (when `/proc/self/status` is available) a 96 MiB RSS delta guard. Defaults are 400 rounds, 96 glyph entries, and 64 lifecycle iterations; `KIWI_TEXT_STRESS_ROUNDS`, `KIWI_TEXT_STRESS_ATLAS_ENTRIES`, `KIWI_TEXT_STRESS_LIFECYCLES`, and `KIWI_TEXT_STRESS_MAX_RSS_KIB` are explicit overrides. The stress output is a bounded regression check, not a frames-per-second claim.

`make bench-compare` validates schema version, CPU scope, iteration/warm-up configuration, component/workload set, and each component's exact scope before producing deltas. It labels a comparison as not same-system when kernel/architecture or LuaJIT version differs. It needs `jq`; cross-machine deltas remain diagnostic rather than a performance claim.

## Profiling and changes

The initial unchanged printable-output profile used 1,000 parser/state iterations with LuaJIT's sampling profiler. `Damage:mark_range`/`mark` accounted for 42% of samples and `Attributes.resolve` for 9%. LuaJIT trace output also showed repeated damage-loop unroll fallbacks. The M1.5 follow-up profile, using the production direct state sink, reduced damage to 6%; expected row allocation during scrolling then dominated the printable workload. `perf` was unavailable on this host, so the profile evidence is LuaJIT `-jp` sampling and `-jv` trace diagnostics.

The resulting changes are intentionally local:

- a direct state sink avoids allocating a print action table for each production glyph while retaining callback/action-table mode for parser and conformance tests;
- common append-only damage updates extend the active tail range in place; arbitrary insertion/merge behavior remains covered by tests;
- attribute flag resolution uses fixed fields instead of iterating the flag map per glyph;
- the live loop caps one PTY service turn at 4 KiB by default and exposes the last read size/count in F4 diagnostics.

Before those changes, the untouched M1 schema-version-2 parser/state run used 300 iterations but no warm-up or normalized memory methodology. It recorded 13.1891 ms printable ASCII, 7.6687 ms SGR-heavy, 29.5513 ms cursor/erase, 31.3167 ms scrolling-newlines, and 44.4182 ms mixed-captured-style mean CPU time. Those numbers establish the original measured state, but they are not a valid before/after comparison: M1.5 changes both the production print sink and the benchmark methodology. The schema separates such legacy data from M1.5 results for that reason.

### M2 ASCII investigation

On 2026-08-10, the M2 tree and the exact pre-M2 M1.5 commit `d05e5de` were measured in detached worktrees on this host with an identical 100-iteration warm-up and 500 measured parser/state printable-ASCII iterations. M1.5 measured 0.7110 ms p50 and 2.0400 ms p99; the initial M2 path measured 5.2075 ms p50 and 7.6321 ms p99. M2 now uses a safe ASCII fast path that skips Unicode property classification, interns singleton ASCII code-point lists, and reuses its transient grapheme context. The controlled M2 result fell to 1.7480 ms p50 and 4.4120 ms p99.

The remaining 146% p50 and 116% p99 difference still exceeds the project's 25% p50 / 50% p99 investigation thresholds. The added cost is in cluster-bearing terminal-state writes rather than UTF-8 decoding, parser-only action construction, glyph shaping, or GPU packing. M2 keeps the text pipeline separately measured and bounds its native caches, but it does not claim the M1.5 ASCII kernel cost is regression-free; reducing single-cluster terminal metadata cost remains future performance hardening work.

## Representative local baseline

This host ran Fedora 43/Linux 7.1.6-101.fc43.x86_64 on an Intel Core i7-1355U (12 online logical CPUs, `performance` governor, affinity `0-11`, frequency scaling reported at 28%), Intel Iris Xe Graphics, and LuaJIT 2.1.1767980792 with the default enabled JIT features. The following `make bench` run used 50 measured iterations and 10 warm-ups on a dirty worktree at `1e0ab88`; it is a reproducibility reference only.

| Full CPU workload | Mean | p95 | p99 | Bytes/CPU second |
| --- | ---: | ---: | ---: | ---: |
| printable ASCII | 3.8209 ms | 7.8896 ms | 10.4395 ms | 1,432,123 |
| SGR-heavy | 2.7940 ms | 6.7903 ms | 7.1824 ms | 2,061,531 |
| cursor/erase TUI | 9.4808 ms | 13.1117 ms | 13.3690 ms | 546,790 |
| scrolling newlines | 7.9497 ms | 12.2654 ms | 15.4407 ms | 1,908,006 |
| mixed captured style | 46.7382 ms | 62.9112 ms | 65.1599 ms | 168,428 |

The 80x24 contiguous damage microbenchmark averaged 0.0142 ms; the intentional fragmented case averaged 25.1135 ms. The difference is expected: the latter creates 640 disjoint intervals and remains a useful regression boundary for range-list behavior.

The same run measured real full-screen scroll at 0.0336 ms mean for 80x24 and 0.0604 ms for 240x80. Those measurements include row-reference movement, entering-row allocation, bounded scrollback handoff, damage discovery, and clear; they are not the M0 synthetic scrolling workload.

## Real-PTY burst checks and thresholds

`make bench-burst` validates bounded live service rather than only in-memory parsing. It sends 1 MiB printable output, at least 1 MiB of mixed ANSI output, and an interleaved DSR-response stream through `forkpty`. The optional 10 MiB printable case is enabled with `KIWI_BURST_10MB=1`.

The checked limits are exact defaults, overrideable only for deliberately different test environments:

- `KIWI_PTY_READ_BUDGET=4096`: no one live-loop turn reads more than 4 KiB;
- `KIWI_BURST_MAX_SERVICE_MS=250`: a service turn above 250 ms fails the run;
- `KIWI_BURST_MAX_HEAP_KIB=65536`: retained Lua heap growth above 64 MiB fails the run.

The harness records a service-time distribution, maximum turn, output count, parser counters, retained Lua heap/RSS deltas, and canonical final snapshots for the printable and mixed streams. It also proves that a terminal-generated response was written while output was active. `frame_deadline_slots_serviced_while_output_active` is a headless 30 Hz scheduling proxy, not a presented-frame count; presentation is not measurable without creating a native window.

On the representative host, the 4 KiB-bounded 10 MiB printable run completed in 15.463 s with a 13.479 ms p95 service turn, a 30.208 ms maximum, and 4.158 MiB retained Lua heap growth. The 1 MiB ANSI-mixed stream had a 20.054 ms p95 and 35.103 ms maximum. These observations are not threshold values; the explicit limits above are the regression checks.

Results depend on CPU governor, thermals, JIT state, allocator state, kernel load, and host graphics stack. Do not compare these values with other terminal emulators or treat them as a latency service-level objective.
