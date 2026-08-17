# Kiwi M1.5, M2, and M2.5 benchmarks

M1.5 measures the real LuaJIT terminal pipeline in layers instead of inferring terminal performance from the older synthetic renderer model. The benchmarks are reproducible CPU measurements, not a claim of end-to-end terminal or GPU latency.

```sh
make bench
KIWI_BENCH_ITERATIONS=100 KIWI_BENCH_WARMUP=20 make bench
make bench-write
KIWI_WRITE_BENCH_ITERATIONS=500 KIWI_WRITE_BENCH_WARMUP=100 make bench-write
make bench-burst
KIWI_BURST_10MB=1 make bench-burst
make pacing
KIWI_PACING_SAMPLES=120 KIWI_PACING_WARMUP_FRAMES=20 make pacing
make bench-longrun
KIWI_LONGRUN_HISTORY_LIMIT=2048 KIWI_LONGRUN_HISTORY_LINES=4096 make bench-longrun
make device-soak
KIWI_DEVICE_SOAK_SECONDS=600 make device-soak-native
make device-loss-sim
make text-corpus-review
KIWI_TEXT_CORPUS_ARTIFACT=/absolute/path/review.json make text-corpus-review
KIWI_MAX_FRAMES=240 make text-corpus-demo
make text-lab
make text-lab BACKENDS=atlas,msdf
make text-lab-demo BACKEND=atlas
KIWI_LIGATURES=1 KIWI_CALT=1 make bench-text
make profile-text
KIWI_PROFILE_MODE=mixed KIWI_PROFILE_TRACE=1 make profile-text
KIWI_PROFILE_MODE=ascii_full KIWI_PROFILE_ITERATIONS=10000 make profile-text
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

## M9 frame pacing methodology

`make pacing` is an opt-in native Linux measurement. It drives a fixed child
that emits 150 short output records at 40 ms intervals, warms up 30 successful
frames by default, and writes the ignored, schema-version-1 aggregate report
`bench/results/<UTC timestamp>-pacing.json`. `KIWI_PACING_SAMPLES` bounds each
retained distribution (default 240) and `KIWI_PACING_WARMUP_FRAMES` changes the
excluded frame count. The target exits successfully with an explicit skip when
neither X11 nor Wayland is available, which is the intended headless-CI result;
it does not manufacture a presentation metric. The encoded aggregate is capped
at 64 KiB and contains no raw sample or event-payload arrays.

The report uses GLFW's monotonic clock at four markers: accepted PTY input,
first readable PTY output, renderer update start, and return from the successful
`Renderer:render` call. It keeps aggregate p50/p95/p99/mean/min/max and
standard deviation, plus bounded invalidation-reason counts. It retains no
keys, terminal output, clipboard data, commands, display identifier, or raw
event timestamps. A full artifact records revision/dirty state, LuaJIT, CPU,
kernel, best-effort GL/Vulkan adapter/driver inventory, governor, affinity,
power profile, scheduler nice value, graphical session kind, best-effort
display refresh rate, FIFO present mode, and PTY read budget. Missing commands
produce `unavailable` fields.

The four metric fields are intentionally distinct:

| Field | Meaning | Does not measure |
| --- | --- | --- |
| `frame_cpu_ms` | CPU time from renderer update start through the return after `wgpuSurfacePresent` | GPU execution, compositor work, or panel scan-out |
| `frame_interval_ms` | interval between successful render returns; standard deviation is the report's pacing variance | monitor refresh accuracy or missed-vblank count |
| `output_to_present_ms` | coalesced PTY output through the following successful render return | photons reaching the display |
| `input_to_present_ms` | coalesced bytes sent to the PTY, then a later readable output, through that render return | local actions, input with no observed output, and a universal input-latency figure |

`display_scanout_latency` is always explicitly unavailable without external
display/compositor measurement such as presentation feedback or a photodiode.
`gpu_execution_latency` is likewise unavailable: optional wgpu timestamp query
results are asynchronous per-pass work and cannot establish terminal-event to
display latency. The fixture usually has no user input, so an unavailable
`input_to_present_ms` field is expected for the automated baseline. To measure
an interactive command, run Kiwi with `KIWI_PACING_REPORT=1`, send a command
that visibly responds, and retain the separate local artifact; do not compare
hosts, drivers, power modes, or measurement scopes as though they were the
same baseline.

## M9 long-running history and cache profile

`make bench-longrun` writes an ignored schema-version-1
`bench/results/<UTC timestamp>-longrun.json` report. Its deterministic first
phase feeds 8,192 short Unicode lines through the production parser/state into
a 4,096-row primary scrollback ring. Every 64 lines it applies sparse ANSI
cursor writes, alternates 80- and 79-column resize paths, shapes the visible
viewport, and records CPU, damage, layout/cache, heap, and RSS metrics. It then
shapes the oldest and newest history view. The second phase runs the existing
bounded native text stress workload, which exercises unique glyph pressure,
combining/CJK/emoji/fallback, CSI edits, repeated font-system lifetime, and
atlas/fallback caps. The report carries the exact workload configuration and
host metadata; it has no terminal text, raw history, glyph bitmap, or sample
array and is capped at 64 KiB.

The documented limits are a 4,096-row history ring, 96 glyph-atlas entries,
32 fallback-cache entries, and a 384 MiB RSS-delta guard. Override them only
to establish a separately labeled environment with
`KIWI_LONGRUN_HISTORY_LIMIT`, `KIWI_LONGRUN_HISTORY_LINES`,
`KIWI_LONGRUN_BATCH_LINES`, `KIWI_LONGRUN_ATLAS_ENTRIES`,
`KIWI_LONGRUN_TEXT_ROUNDS`, `KIWI_LONGRUN_LIFECYCLES`, and
`KIWI_LONGRUN_MAX_RSS_KIB`. The profile creates no native window, WGPU
resource, or presentation target. Its `gpu_renderer` and `display_pacing`
fields are consequently explicit unavailable states; use `make pacing` for the
separate native present-call measurement.

Compare only reports with identical `result.configuration` using:

```sh
./script/compare-longrun bench/results/baseline-longrun.json bench/results/candidate-longrun.json
```

The comparator rejects a mismatched schema or workload configuration, then
reports deltas for history batch/navigation p95, heap/RSS deltas, and text-cache
CPU/failure counts. It does not establish a cross-host regression. Treat each
output as measured CPU/resource data only; changes in driver, governor,
thermals, font inventory, allocator, or kernel require a separately qualified
comparison.

### Baseline finding and narrow repros

Measured on the Fedora 43 primary Linux host on 2026-08-10 with the default
4,096/8,192 history configuration and the 384 MiB guard: 128 batches had
7.757 ms mean / 21.724 ms p95 CPU time, the two history-navigation layouts had
1.383 ms mean / 1.856 ms p95, and the profile retained 90,901 KiB Lua heap and
249,352 KiB RSS. The text-cache phase reached its 96-entry atlas cap, reported
two insertion failures, and retained 2,076 KiB heap / 4,024 KiB RSS. The
3,106-byte local report explicitly marked GPU/renderer and display pacing
unavailable.

[Inference] The history phase is the dominant retained-memory boundary in this
configuration: it retains full terminal rows while also exercising visible-row
layout, whereas the independent text-cache phase has a much smaller measured
RSS delta. That does not establish which allocation type dominates without a
heap profiler. Reproduce the history boundary with:

```sh
KIWI_LONGRUN_HISTORY_LIMIT=4096 KIWI_LONGRUN_HISTORY_LINES=8192 make bench-longrun
```

Use the report's `history.memory`, `history.batch_cpu_ms`, and
`history.history_navigation_cpu_ms` fields before considering a narrow change
in `terminal/scrollback.lua` or viewport/layout cache ownership. Reproduce the
separate atlas/fallback boundary with:

```sh
KIWI_LONGRUN_ATLAS_ENTRIES=96 KIWI_LONGRUN_TEXT_ROUNDS=400 make bench-longrun
```

The 384 MiB guard is a [Inference] regression boundary with headroom above this
host's observed result, not a universal memory target or evidence that a lower
memory configuration is unsupported.

## M9 device-loss and extension lifecycle soak

`make device-soak` is the short, deterministic CI-friendly check. Its default
32 cycles build a fresh pass graph and semantic-resource registry, exercise a
resize/minimize/restore lifecycle marker, alternately disable a failing trusted
optional pass, and verify that every fake owned resource is released and no
registry retains an active pass after shutdown. It does not create a window,
adapter, device, surface, or native GPU resource; its results establish only
Lua lifecycle and ownership behavior.

`make device-soak-native` is an opt-in graphical companion. On Linux it skips
with an explicit message when neither `DISPLAY` nor `WAYLAND_DISPLAY` is
available; on macOS it uses the native Cocoa session. It runs `/usr/bin/yes` in
Kiwi, repeatedly invokes GLFW resize, iconify, and restore operations, and
loads a test-only optional pass that disables itself on encoding. The run ends after
`KIWI_DEVICE_SOAK_SECONDS` (default `10`); a longer local run remains bounded,
for example:

```sh
KIWI_DEVICE_SOAK_SECONDS=600 make device-soak-native
```

The native command exercises the current display/compositor path rather than a
portable leak detector. [Inference] Passing it shows that this workload reached
its configured lifecycle calls and completed cleanup on that host; it does not
prove absence of driver, compositor, or WGPU leaks.

Kiwi handles a WGPU device-loss callback by recreating the device, surface, and
renderer once while retaining the existing window, terminal state, PTY, and
font. Surface-status failures request reconfiguration; a second loss or another
native GPU error exits with bounded adapter/pass diagnostics. `make
device-loss-sim` drives that policy through a clearly synthetic error at a
bounded frame count. It verifies cleanup/recreation control flow where a real
device loss cannot be induced, but does not observe a driver callback. Record a
real callback separately when a platform exposes a safe fault-injection path.

## M9 redraw scheduling observation

`make power-smoke` writes an ignored, schema-version-1
`bench/results/<UTC timestamp>-power.json` report. The graphical fixture sends
one fixed synthetic PTY input (recorded separately from physical input), emits
three short output bursts, requests a 10 Hz trusted extension animation, and
uses the bounded GLFW lifecycle calls from `device-soak`; it exits after
`KIWI_DEVICE_SOAK_SECONDS` (default `6`). The target skips without a graphical
display. It aggregates loop wakeups, requested wait time, active/idle/minimized
observed durations, successful renderer returns, deferred presentation, input
and output event counts, invalidation reasons, and extension-animation frames.
It retains no event payload.

The report does **not** measure battery discharge, CPU package energy, GPU
energy, compositor work, panel scan-out, or operating-system wakeup attribution.
A `wakeup` is only a return from Kiwi's GLFW wait loop. GLFW has no portable
compositor-occlusion callback, so occlusion is explicitly unavailable. A
zero `minimized` duration means that the platform did not deliver an iconify
state during that particular run; it is not evidence that the window was not
occluded or that the minimized branch ran.

Policy is intentionally conservative: visible sessions wait at most 50 ms so
the single Lua thread can service the nonblocking PTY and GLFW; pending output,
input, resize, local actions, or configuration each coalesce into the next
render. A visible blinking cursor schedules one 0.5-second deadline. Iconified
windows retain terminal state and invalidation but avoid surface acquire/present
and use a 250 ms maximum wait; restoration reconfigures then presents the latest
state. DEC synchronized output has the same defer-without-drop behavior.
Extension animation deadlines remain bounded by
`KIWI_EXTENSION_MAX_ANIMATION_HZ` (1/60 through 60 Hz) and do not run while a
window is minimized.

On the Fedora 43 Wayland host, the initial six-second `make power-smoke` report
observed 130 GLFW-loop wakeups (21.56 Hz), 26 successful renderer returns, three
output events, 10 extension-animation frames, one synthetic input event, 0.603
active seconds, and 5.426 idle seconds. It observed zero minimized seconds and
zero physical input events: the programmatic GLFW iconify requests did not yield
an iconify state on this host, and the fixture intentionally uses no physical
keyboard injection. Those are unavailable states, not favorable power or latency
results. Re-run with real typing and a compositor that reports iconification
before comparing the corresponding counters; compare only matching duration,
extension cadence, display/session, driver, governor, kernel, and source
revision.

Regression validation is behavioral rather than a wattage threshold: `make
test` proves deadline coalescing and minimized presentation gating; `make
power-smoke` must remain bounded, produce a report below 64 KiB, retain no
payload, and show extension animation frames when its fixture is active. A
future platform energy integration must be versioned separately rather than
turning these counters into an energy claim.

## M8 text corpus and review protocol

`src/kiwi/text/benchmark_corpus.lua` is the versioned, reviewable corpus for
text-backend evaluation. It deliberately contains six short scenarios rather
than an opaque prose sample or bundled font: ASCII, combining marks, CJK,
emoji, ligature candidates, and dense box-drawing/status UI. Each entry is at
most 256 input bytes; the checked-in module records its source and license
classification next to the literal text. ASCII, ligature, and dense-UI strings
are Kiwi-authored. Combining, CJK, and emoji scenarios are also short
Kiwi-authored arrangements; their code-point categories are based on the
checked-in Unicode 17 data, whose [Unicode License v3](https://www.unicode.org/license.txt)
permits associated documentation. No third-party prose or font asset is
distributed by this corpus.

`make text-corpus-review` writes an ignored, machine-readable
`bench/results/*-text-corpus.json` artifact. It records the corpus version and
literals, byte/code-point/EGC/terminal-column counts, source/license fields,
and the benchmark environment. That environment includes CPU model, kernel,
LuaJIT, governor, affinity, and best-effort GL/Vulkan renderer and driver
inventory; an unavailable command is reported as `unavailable`. The inventory
does not prove that wgpu selected a particular adapter.

`make bench-text` uses the same corpus for every measured text layer and embeds
the corpus version, literals, ligature/calt settings, and resolved
primary/fallback font inventory in its result. This is the current bitmap-atlas
baseline; an experimental backend must consume the unchanged corpus and retain
the same semantic manifest before any numbers can be compared. Run the default
shaping configuration and, when ligatures are
under review, a separate `KIWI_LIGATURES=1 KIWI_CALT=1 make bench-text` result.
Run the bounded native presentation with `KIWI_MAX_FRAMES=240 make text-corpus-demo`, retain a
compositor screenshot beside the JSON manifest, and record the primary/fallback
font paths, content scale, desktop session, and backend setting. The screenshot
is the explicit visual review artifact; Kiwi does not claim a portable
pixel-difference metric across different fonts, drivers, or compositors.

Review semantic output first: the manifest's input bytes, code-point count,
extended-grapheme count, and terminal columns must agree. Then review the
baseline and candidate screenshots side by side for missing glyphs, overlap,
clipping, wide-cell occupancy, fallback changes, ligature behavior, and dense
UI alignment. Record glyph/instance/cache/fallback counters and CPU p50/p95/p99
from the same host, including the `text_backend` descriptor's requested/active
selection and fallback status, before drawing a performance conclusion. A different font,
font fallback result, content scale, Unicode data version, driver, adapter,
governor, kernel, or iteration scope makes results non-comparable; this protocol
has no automatic threshold or cross-machine ranking.

## M8 text laboratory report

`make text-lab` is the developer-facing entrypoint for controlled backend
comparison. It always puts `atlas` first, then evaluates the comma-separated
candidate names in `BACKENDS` (default `atlas`; at most four names after input
validation). Its ignored `bench/results/*-text-lab.json` artifact records the
same corpus manifest, host/runtime metadata, font inventory, shape options,
backend descriptors, and bounded CPU samples for `backend:update` after
parser/state setup. The scope includes CPU row shaping and glyph-cache work;
it excludes parser time, queue writes, GPU execution, compositor, and
presentation. It is therefore not an end-to-end latency or visual-quality
measurement.

Normal Kiwi runs ignore experimental backend variables and use `atlas`.
`make text-lab-demo BACKEND=<name>` is the only documented native selection
path; it sets `KIWI_TEXT_LAB=1` and `KIWI_TEXT_LAB_BACKEND=<name>` for the
bounded corpus child. If a requested backend resolves to atlas with
`fallback=true`, the report lists it in `unavailable_environments`; its CPU
samples demonstrate the fallback path only, not a prototype comparison.

Read `measured_facts`, `unavailable_environments`, and `inference` as separate
sections. A report never promotes a backend automatically. Use the explicit
template in [TEXT_LAB.md](TEXT_LAB.md): capture matching native screenshots,
confirm semantic counters and descriptors, then make a manual recommendation.

## M2 native-text measurements

`make bench-text` is deliberately separate from `make bench`: it defaults to 10 measured iterations and 3 warmups, writes `bench/results/<UTC timestamp>-text.json` with schema version 2, and does not alter the M1.5 schema. Schema 2 adds the versioned corpus, shape settings, and resolved font inventory, so it must not be compared to prior schema-1 text results. It reports each text-corpus scenario at these layers:

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

## M2.5 write-path attribution

`make bench-write` writes schema-version-4 `bench/results/<UTC timestamp>-write.json`. It keeps the M1.5 and M2 schemas intact and records the selected primary font path, pixel height, atlas dimensions/capacity, fallback bounds, HarfBuzz feature options, Unicode version, revision/dirty state, LuaJIT settings, kernel/governor/affinity, iteration count, and exact CPU scope.

Each ASCII full-dirty-row and Unicode combining/CJK/emoji/fallback workload is measured at these deliberately separate stages:

| Stage | Timed work |
| --- | --- |
| UTF-8 decode | incremental byte decoding only |
| ASCII cell mutation control | two legacy and two direct mutation blocks, each with a fresh LuaJIT trace and 16 fresh writes per timed sample |
| parser/cluster mutation/logical damage | production parser sink, cluster/width mutation, and both damage streams |
| row-run construction/fallback | visible cluster inspection, primary coverage, fallback decisions, and same-face runs |
| HarfBuzz shaping | prebuilt runs through HarfBuzz only |
| HarfBuzz/atlas/glyph records | shaping through raster cache/atlas and Lua glyph-record construction |
| renderer glyph-record packing | prebuilt shaped glyphs through the real 48-byte FFI record packer |
| shape invalidation cursor-only | cached static layout with cursor-only logical damage |
| full parser-to-glyph record | parser through text glyph records; PTY and GPU work excluded |

Counters include decoded scalars, parser actions/errors, ASCII fast-path use, Unicode property and grapheme-boundary checks, width calls, created/extended clusters, changed/logical/text-dirty cells and ranges, invalidated/reshaped rows, run construction/shaping, shaped code points/glyphs, bounded primary-ASCII coverage-cache probes/hits, fallback decisions, glyph-cache hits/misses, and emitted glyph records. The ASCII control includes both p50/p95/p99 series and is the only in-process legacy comparator; trace flushing occurs between whole blocks, rather than mutating the method on each sample, to avoid measuring JIT invalidation. Each timed sample contains 16 fresh state/parser writes to avoid sub-millisecond clock quantization; throughput and counters include all 16 writes. The full stage ends at CPU glyph-record construction: PTY syscalls, queue writes, GPU atlas uploads, GPU execution, compositor scheduling, and presentation are excluded.

`script/compare-bench` accepts the original schema 3 and M2.5 schema 4, but never mixes them. It rejects differing iteration/warm-up or M2.5 font/atlas/shaping configuration and timing scope. Schema 3 also rejects a row-set mismatch. Schema 4 compares only the shared rows and explicitly lists added or removed stages, so benchmark instrumentation can grow without falsely comparing a new stage to absent historical data. Results stay local/ignored; compare only identical scopes on the same or closely controlled host.

`make profile-text` stores ignored sampling output in `bench/profiles/`; `KIWI_PROFILE_TRACE=1` also stores the corresponding LuaJIT `-jv` trace. The final 100,000-iteration no-scroll ASCII parser/state profile sampled 99% compiled code; its trace retains the parser byte loop and direct ASCII cell mutation. The 10,000-iteration ASCII-full path sampled 63% compiled, 19% interpreted, and 15% GC, concentrated in layout run/glyph table work and HarfBuzz/atlas boundaries. The 100,000-iteration combining, CJK, and mixed parser/state profiles sampled respectively 96% compiled/4% GC, 66% compiled/24% interpreted/10% GC, and 84% compiled/7% interpreted/9% GC; their hotspots are Unicode property lookup, grapheme/width policy, cluster and damage work. The traces preserve those property/width exits rather than bypassing Unicode semantics. The actual replay and 8 MiB live-PTY profiles are dominated by intentional scroll/screen allocation (47% and 60% GC respectively), so they are evidence for burst/replay behavior, not an ASCII mutation-cost claim.

### M2.5 manual Wayland release checklist

This is a release gate for an interactive Wayland session, not an automated claim. No additional terminal test tool is required.

- Launch `make run`, then generate at least 10,000 numbered lines from the child shell while repeatedly resizing the window between small and large grids.
- During and after output, use `Shift+PageUp`/`Shift+PageDown` at both history boundaries; verify stable text, cursor visibility, and no orphaned wide/continuation cells.
- Repeat with the bundled text child (`KIWI_MAX_FRAMES=240 make text-demo`), include CJK/combining/emoji output, and use `--inspect` on a continuation and an anchor.
- Close the window while output is active and confirm the child exits; retain the command, desktop/session details, and any visual anomaly with the release evidence.

`make bench-compare` validates schema version, CPU scope, iteration/warm-up configuration, and each shared component's exact scope before producing absolute and percentage p50/p95/p99/mean/throughput deltas. It also lists changed counters shared by each compared stage. Schema 4 stage additions/removals are labeled rather than compared; all other configuration mismatch is rejected. It labels a comparison as not same-system when kernel/architecture or LuaJIT version differs. It needs `jq`; cross-machine deltas remain diagnostic rather than a performance claim.

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

`make bench-burst` validates bounded live service rather than only in-memory parsing. It sends 1 MiB printable output, at least 1 MiB of mixed ANSI output, a bounded 128 KiB combining/CJK/emoji/PUA stream, and an interleaved DSR-response stream through `forkpty`. The Unicode case validates parser/state canonical output; `bench-text-stress` supplies the complementary shaping, fallback-cache, and atlas-bound checks. The optional 10 MiB printable case is enabled with `KIWI_BURST_10MB=1`.

The checked limits are exact defaults, overrideable only for deliberately different test environments:

- `KIWI_PTY_READ_BUDGET=4096`: no one live-loop turn reads more than 4 KiB;
- `KIWI_BURST_MAX_SERVICE_MS=250`: a service turn above 250 ms fails the run;
- `KIWI_BURST_MAX_HEAP_KIB=65536`: retained Lua heap growth above 64 MiB fails the run.

The harness records a service-time distribution, maximum turn, output count, parser counters, retained Lua heap/RSS deltas, and canonical final snapshots for the printable and mixed streams. It also proves that a terminal-generated response was written while output was active. `frame_deadline_slots_serviced_while_output_active` is a headless 30 Hz scheduling proxy, not a presented-frame count; presentation is not measurable without creating a native window.

On the representative host, the 4 KiB-bounded 10 MiB printable run completed in 15.463 s with a 13.479 ms p95 service turn, a 30.208 ms maximum, and 4.158 MiB retained Lua heap growth. The 1 MiB ANSI-mixed stream had a 20.054 ms p95 and 35.103 ms maximum. These observations are not threshold values; the explicit limits above are the regression checks.

Results depend on CPU governor, thermals, JIT state, allocator state, kernel load, and host graphics stack. Do not compare these values with other terminal emulators or treat them as a latency service-level objective.
