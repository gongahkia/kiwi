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
make bench-interactive
make bench-interactive ARGS='--trials 5 --samples 40 --report bench/results/interactive-candidate.json'
KIWI_PACING_SAMPLES=120 KIWI_PACING_WARMUP_FRAMES=20 make pacing
make pacing-compare BASELINE=/stable/runner/pacing.json CANDIDATE=bench/results/<timestamp>-pacing.json
make pacing-budget BASELINE=/stable/runner/pacing.json CANDIDATE=bench/results/<timestamp>-pacing.json
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

`make bench` defaults to 50 measured iterations and 10 warm-up iterations. It writes schema-version-3 JSON to `bench/results/<UTC timestamp>.json`. `make bench-burst` uses the real nonblocking PTY and writes a separate schema-version-4 `*-burst.json` result. Generated results are intentionally not source-controlled.

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

`make pacing` is an opt-in native graphical measurement on macOS or Linux. It drives a fixed child
that emits 150 short output records at 40 ms intervals, warms up 30 successful
frames by default, and writes the ignored, schema-version-1 aggregate report
`bench/results/<UTC timestamp>-pacing.json`. `KIWI_PACING_SAMPLES` bounds each
retained distribution (default 240) and `KIWI_PACING_WARMUP_FRAMES` changes the
excluded frame count. The fixture always disables workspace layout restore and
persistence so the selected child is the only terminal workload. Linux exits
successfully with an explicit skip when neither X11 nor Wayland is available,
which is the intended headless-CI result; macOS relies on its native graphical
session instead. The report does not manufacture a presentation metric. The
encoded aggregate is capped
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

For input responsiveness during concurrent output, use the acknowledged
interactive benchmark below. This older pacing counter does not establish
that the later output was caused by the input being timed.

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

The manually dispatched self-hosted Linux desktop workflow runs `make pacing`
and `make power-smoke` after its functional qualification, then uploads their
bounded JSON artifacts with the GLFW and GTK compatibility reports. The
protected `desktop-compatibility` environment must provide
`KIWI_PACING_BASELINE`, a readable approved report produced on that exact
runner, and its lowercase SHA-256 in `KIWI_PACING_BASELINE_SHA256`. The
workflow verifies the digest before it runs `make pacing-budget`, so replacing
the file at the approved path is not silently treated as a new baseline. This
is a controlled same-runner regression gate, not a portable performance
threshold, GPU execution measurement, or a substitute for the manual release
checklist below.

`make pacing-compare` rejects any difference in report schema, measurement
configuration, system, runtime, or methodology. It compares measured p95
`frame_cpu_ms`, `frame_interval_ms`, and `output_to_present_ms`; a metric that
is unavailable in both reports is explicitly excluded, while a measured versus
unavailable pair is incompatible. `make pacing-budget` requires at least one
comparable metric and defaults to a 25% p95 regression limit, overridable only
for a separately qualified runner with
`KIWI_PACING_MAX_P95_REGRESSION_PERCENT`. It does not budget input-to-present
when the automated workload does not cause a reply, display scan-out, GPU time,
or power/energy: those remain unavailable measurements rather than favorable
zeros.

## M9 long-running history and cache profile

`make bench-longrun` writes an ignored schema-version-2
`bench/results/<UTC timestamp>-longrun.json` report. Its deterministic first
phase feeds 8,192 short Unicode lines through the production parser/state into
a 4,096-row primary scrollback ring. Every 64 lines it applies sparse ANSI
cursor writes, alternates 80- and 79-column resize paths, shapes the visible
viewport, and records CPU, damage, layout/cache, heap, and RSS metrics. Each
batch separately attributes input/parser, fragmented-update, resize,
visible-layout, and damage-clear CPU time. It then makes eight oldest/newest
history traversals (16 observations by default), separately attributing scroll
and layout CPU time; `KIWI_LONGRUN_NAVIGATION_ROUNDS` changes that labeled
workload. The second phase runs the existing
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
`KIWI_LONGRUN_TEXT_ROUNDS`, `KIWI_LONGRUN_LIFECYCLES`,
`KIWI_LONGRUN_NAVIGATION_ROUNDS`, and
`KIWI_LONGRUN_MAX_RSS_KIB`. The profile creates no native window, WGPU
resource, or presentation target. Its `gpu_renderer` and `display_pacing`
fields are consequently explicit unavailable states; use `make pacing` for the
separate native present-call measurement.

Compare only reports with identical `result.configuration` using:

```sh
./script/compare-longrun bench/results/baseline-longrun.json bench/results/candidate-longrun.json
make bench-longrun-budget BASELINE=bench/results/baseline-longrun.json CANDIDATE=bench/results/candidate-longrun.json
```

The comparator rejects a mismatched schema, workload configuration, system,
runtime, or methodology. It then reports deltas for history batch and phase
p95s, navigation phase p95s, heap/RSS deltas, and text-cache CPU/failure
counts. This makes a same-environment regression comparison, not a cross-host
claim. Treat each output as measured CPU/resource data only; changes in driver,
governor, thermals, font inventory, allocator, or kernel require a separately
qualified new baseline.

`make bench-longrun-budget` adds a same-environment release gate on top of that
comparison. Its defaults allow at most 25% p95 regression for history batch,
history navigation, and text-cache CPU time, and 15% retained-history-heap
growth. Override only for a separately qualified environment with
`KIWI_LONGRUN_MAX_CPU_P95_REGRESSION_PERCENT` and
`KIWI_LONGRUN_MAX_MEMORY_REGRESSION_PERCENT`. These are relative regression
budgets, not portable latency or memory SLOs.

### macOS reflow investigation

On 2026-08-22, the default profile on an Apple M3 (Darwin 25.5.0, arm64,
LuaJIT 2.1.1785763465) attributed a 321.766 ms history-batch p95 almost
entirely to resize/reflow (269.656 ms p95). The current no-op-reflow fast path
reduced that same-machine run to 67.613 ms batch p95 and 2.872 ms resize p95;
input/parser remained the leading phase at 57.221 ms p95. Retained Lua heap was
104,228 KiB and RSS is unavailable on this macOS harness. The path applies only
when every retained primary row is unwrapped and already fits, with no primary
selection, shell/command metadata, kitty placement, or pending-wrap cursor to
remap. Row-count changes and all other column changes use the established full reflow. This is local
same-machine CPU evidence, not a comparison with the Fedora baseline or an
end-to-end terminal latency claim.

### Baseline finding and narrow repros

Measured on the Fedora 43 primary Linux host on 2026-08-10 with the then-
default 4,096/8,192 history configuration and the 384 MiB guard: 128 batches
had 7.757 ms mean / 21.724 ms p95 CPU time, and the former two-observation
history-navigation phase had 1.383 ms mean / 1.856 ms p95. It retained 90,901
KiB Lua heap and 249,352 KiB RSS. The text-cache phase reached its 96-entry
atlas cap, reported two insertion failures, and retained 2,076 KiB heap / 4,024
KiB RSS. The 3,106-byte local report explicitly marked GPU/renderer and display
pacing unavailable. That historical report is not comparable with the current
16-observation navigation workload; establish a new same-machine baseline.

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

Live sessions now wait for host/PTY/process/configuration events or an explicit
deadline. A quiet session can wait indefinitely. A visible blinking cursor
schedules one 0.5-second deadline. Iconified windows retain terminal state and
invalidation but avoid surface acquire/present; restoration presents the latest
state. DEC synchronized output has the same defer-without-drop behavior.
Only children without native exit-watch support retain the 50 ms visible /
250 ms minimized reaping fallback. Linux GLFW may also use a 50 ms fallback for
unsupported GLib descriptor sets; see [ADR 0045](adr/0045-event-driven-host-waits.md).
Extension animation deadlines remain bounded by
`KIWI_EXTENSION_MAX_ANIMATION_HZ` (1/60 through 60 Hz) and do not run while a
window is minimized.

`make idle-wake-smoke` uses a synthetic-input handshake, hides the cursor and
keeps the child quiet for three seconds before exit. An external 30-second
watchdog catches hangs. The gate allows at most 30 host-loop wakes and requires
an indefinite wait. This is a regression budget for a quiet test desktop, not
a promise about arbitrary desktop activity. `--report PATH` preserves JSON;
`--root PATH --record-only` records a historical checkout without enforcing
the new budget. Current power reports count indefinite waits separately, and
state durations measure time inside host waits using the state before the wait;
they exclude parsing/rendering CPU time. Historical reports used intervals
between observations, so those duration fields are not directly comparable.
Measured results and an unresolved desktop outlier are recorded in
[the event-wait evidence](evidence/2026-10-26-event-waits.md).

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

- `KIWI_PTY_READ_BUDGET=16384`: ordinary output service reads at most 16 KiB per window turn, in chunks no larger than 4 KiB. It checks an 8 ms wall-time target after each read/parse chunk and yields when spent. One chunk cannot be preempted. Hot panes share the byte ceiling and rotate priority after a time-limited turn. An already-open Kitty graphics transfer retains its separately divided `KIWI_KITTY_TRANSFER_READ_BUDGET=262144` fast path;
- `KIWI_BURST_MAX_SERVICE_MS=250`: a service turn above 250 ms fails the run;
- `KIWI_BURST_MAX_HEAP_KIB=65536`: retained Lua heap growth above 64 MiB fails the run.

The burst harness uses the same ordinary-output service as the native controllers.
The 8 ms target is checked between chunks; the existing 250 ms service gate
continues to catch unusually expensive individual chunks or delayed turns.
Reports are atomically replaced before testing and after each case, with a
top-level `running`, `failed` or `complete` status. The first failure stops later
cases while retaining earlier results and the failing case's available counters,
memory, snapshot and child status. Parser errors and deadlines trigger bounded
PTY shutdown before reporting; cleanup/snapshot errors are retained separately.
The CLI exits unsuccessfully after saving a failed report. `KIWI_BURST_REPORT`
selects an explicit report path; its parent directory must already exist.
`make test-burst-bench` exercises these paths with real PTY children, including
service/heap rejection, truncated output, snapshot/response failures, nonzero
child exit, parser/setup errors and timeout cleanup. It is part of `make check`.
The harness measures elapsed and per-service-turn time through the native process clock: `CLOCK_MONOTONIC` on Linux and `CLOCK_MONOTONIC_RAW` on macOS. Its JSON metadata explicitly identifies this as monotonic wall time; it is not the `os.clock` CPU timer used by the in-memory component suite. The harness records a service-time distribution, maximum turn, output count, parser counters, retained Lua heap/RSS deltas, and canonical final snapshots for the printable and mixed streams. It also proves that a terminal-generated response was written while output was active. `frame_deadline_slots_serviced_while_output_active` is a headless 30 Hz scheduling proxy, not a presented-frame count; presentation is not measurable without creating a native window.

On the representative host, the 4 KiB-bounded 10 MiB printable run completed in 15.463 s with a 13.479 ms p95 service turn, a 30.208 ms maximum, and 4.158 MiB retained Lua heap growth. The 1 MiB ANSI-mixed stream had a 20.054 ms p95 and 35.103 ms maximum. These observations are not threshold values; the explicit limits above are the regression checks.

Results depend on CPU governor, thermals, JIT state, allocator state, kernel load, and host graphics stack. Do not compare these values with other terminal emulators or treat them as a latency service-level objective.
## Configuration replacement

`make bench-configuration-reload` measures palette and font/resize staging at
0, 2,000 and 10,000 retained lines. `KIWI_RELOAD_HISTORY` selects one history
size (0–20,000); `KIWI_RELOAD_ITERATIONS` selects 1–100 samples (default five).
Each case warms once, constructs real fonts and renderer-neutral prepared
buffers, rejects every candidate, checks that the live state/history survive,
and bounds retained Lua growth after collection. JSON reports contain CPU and
monotonic wall-time distributions, Lua heap and sampled process RSS.

The scope excludes GPU allocation/upload/presentation and PTY resize. Sampled
RSS is current resident memory, not the operating system's high-water mark or
GPU memory. macOS observations use `MACH_TASK_BASIC_INFO`; Linux observations
use `/proc/self/statm`. The existing burst, long-run and text-stress workloads
now use the same sampler. `make native` must build the matching bridge.

The first 2026-10-25 Intel macOS run is retained in
`evidence/2026-10-25-macos-reload-baseline.json`. At 10,000 lines, palette
staging had 901 ms p95 wall time; font/resize staging had 2,813 ms p95 and
sampled peak process RSS of 1,582 MiB. These are unacceptable interactive
costs and identify state-copy/reflow optimization work; they are not terminal
performance-parity evidence. Repeat the same workload after changes and keep
machine, fonts and execution conditions comparable.

The matching five-sample rerun is retained in
`evidence/2026-10-25-macos-reload-optimized.json`. Reflow now resolves position
mapping on demand, and configuration staging avoids duplicating source cells
before reflow creates independent destination cells. Immutable grapheme arrays
remain shared; mutable terminal cells and image residency remain isolated.

| 10,000-line case | Baseline | Optimized |
| --- | ---: | ---: |
| Font/resize wall p95 | 2,813 ms | 1,925 ms |
| Font/resize additional Lua heap peak | 1,041 MiB | 395 MiB |
| Font/resize sampled process RSS peak | 1,582 MiB | 1,187 MiB |
| Palette wall p95 | 901 ms | 1,033 ms |
| Palette CPU p95 | 893 ms | 735 ms |

The memory reduction is substantial, but large-history replacement remains too
slow. Palette wall time increased despite lower CPU time; these short runs do
not establish a consistent latency improvement. Neither report measures GPU
staging, displayed latency or competitor performance. Incremental replacement
and cheaper retained-history storage remain performance work.

## Fresh-process startup and acknowledged interaction

`make bench-interactive` runs three fresh processes per mode, with five warmup
inputs and 20 measured inputs in each process. Modes are idle and saturated
background output. It uses the real WGPU controller, synthetic text callbacks,
a raw PTY child, production parser/model/packing and successful compositor
presentation returns. Both GLFW and GTK WGPU hosts are supported; GTK GL is
explicitly rejected. Python 3 and a graphical session are required.

```sh
make bench-interactive
make bench-interactive ARGS='--trials 5 --samples 40 --report bench/results/interactive-candidate.json'
KIWI_HOST=gtk xvfb-run -a ./script/bench-interactive --report bench/results/interactive-gtk.json
make test-interactive-bench
```

The parent records `CLOCK_MONOTONIC` on Linux or `CLOCK_MONOTONIC_RAW` on macOS
immediately before creating each process. The child checks that its native
clock name matches the parent. Darwin's raw continuous clock includes sleep
and avoids its calendar/boot-time-based, microsecond-resolution
`CLOCK_MONOTONIC` path; see [Apple's implementation](https://github.com/apple-oss-distributions/Libc/blob/main/gen/clock_gettime.c).
Reports record the clock in configuration, and relative comparison refuses
mixed clock domains. Backwards timestamps still fail; diagnostics retain the
negative delta and report precise observed/reference values in the error. Startup ends at the
first successful presentation return; a second marker requires the controlled
child's readiness text in the visible model. This measures a fresh application
process with normal filesystem/driver caches and a fixed Python child, not a
cold-cache launch or the user's login-shell startup.

Only one numbered input may be outstanding. Its acknowledgment requires a
matching title header and complete visible model text, including across split
PTY reads. Unrelated output, old acknowledgments and unrelated presentations
cannot finish a sample. The header precedes the text so completing the text
causes normal render damage. Saturated output starts after the first warmup
input, preserving the startup handshake; its nonblocking queue is bounded to
8 KiB and it scrolls below the reserved acknowledgment row. Before the first
input it repaints readiness on PTY resize, using SIGWINCH and a wakeup pipe;
initial native allocation must not leave the fixture waiting for displaced text.
The load sanity check reserves 256 bytes per acknowledgment for protocol
overhead and requires at least another 4 KiB of output. It does not require
4 KiB per input: a quicker acknowledgment can complete before that much output
is consumed. After the first input, the producer continues generating traffic
whenever the PTY is writable.

Reports preserve per-process startup samples, raw bounded input distributions,
parser/presentation phase splits, sampled peak RSS, output-byte counts, actual
cell/grid/font geometry and environment/revision metadata. Geometry changes
invalidate a trial. The window requests 800×480 logical points, uses 18-pixel
font settings and a 16 KiB cooperative PTY read ceiling; actual metrics depend on host scale
and installed fonts and are recorded. The 20 ms inter-input interval is test
scheduling, not a production timer. Initial source/OS startup, input encoding,
child scheduling, PTY transit and rendering CPU work are included within their
named boundaries. Physical input delivery, IME, GPU completion, compositor
feedback and panel scan-out are not measured.

Use `--read-budget BYTES` (1–1048576, default 16384) for controlled output
scheduling experiments, and `--traffic styled-unicode` for coloured, bold,
italic, underlined, combining and wide-character output. ASCII is the default.
The chosen traffic and byte budget are recorded in each trial's configuration;
compare like workloads and geometry. These options do not change product defaults.

The output defaults to ignored `bench/results/interactive.json`; companion
`*-logs/` folders retain trial diagnostics. Reports are atomically updated with
`running`, `failed` or `complete` status. A failed run retains completed trials
and a failure record and replaces any previous report; only `complete` is a
usable baseline. Defaults produce three independent startup observations and
60 measured input observations per mode. Pooled input percentiles are
correlated within processes, not 60 independent process-level observations.
Do not infer statistical confidence or competitor performance from them.

Each trial also retains bounded lifecycle diagnostics: the first Lua window-close
request and its call stack, the first observed close flag, and the child's status
before and after PTY shutdown. A signal sent during cleanup is therefore distinct
from a child that exited during the workload. A normal application return before
all measurements finish is a failed trial with an explicit JSON reason.
`make test-interactive-trial` exercises these paths with a controlled headless
host and real PTY children, including exception and occlusion failures; it does
not qualify native window behaviour.

After the application exits, each trial records `jit_snapshot`: retained trace
count, highest trace number, IR instruction count and emitted machine-code bytes.
The interpreted inspection scans all 16-bit trace identifiers, including holes,
and installs no profiler or trace-event callbacks during the workload. It runs
after timing and resource samples, and does not change execution mode. These
are surviving traces after application cleanup, not historical compilation or
flush counts; a small snapshot cannot establish whether a cache flushed earlier.
Diagnostic failure is reported separately and cannot replace the trial failure.

Every acknowledgment, including warmup, must complete within two seconds.
Trials also have 30-second internal and 40-second external watchdogs. These
are gross failure gates, not latency targets or a relative performance-regression
budget. The CLI caps trials, samples, warmup and scheduled intervals; invalid
arguments leave an existing report untouched. Core tests verify partial-message
handling, stale/unrelated acknowledgments, clock/order errors and incomplete
measurements. `make test-interactive-bench` checks CLI bounds and failed-report
replacement without a graphical host. CI exercises one short trial per mode on
macOS and Linux GLFW/GTK WGPU, retaining reports and logs; GitHub execution is
separate from local qualification.

### Sustained runs and regression budgets

`script/bench-interactive --mode saturated --traffic styled-unicode --trials 1
--samples 120 --warmup 6 --soak-seconds 600 --report /tmp/kiwi-soak.json`
spreads measured inputs over at least ten minutes. Use a single shell line.
The interval replaces `--interval-ms`; warmup adds time before measurement.
Durations are bounded to 60–1800 seconds, with at least 20 measured inputs.
The two-second response ceiling remains unchanged; total watchdogs expand to
cover the requested schedule. CI runs a 60-second version on both Linux hosts
and both macOS architectures. CI configuration is not evidence of a remote pass.

Post-warmup resource observations include process RSS, Lua heap and process CPU
without forcing garbage collection. At most 256 observations are retained.
Growth is the difference between the medians of the final and initial quarters,
not a single noisy allocation. Default gates are 64 MiB RSS growth, 16 MiB Lua
heap growth and 1 GiB peak RSS. These conservative ceilings catch substantial
regressions; they do not prove leak freedom or acceptable idle power. This
workload scrolls a region below the acknowledgment row and does not qualify
full scrollback retention. Partial samples, resource observations and surface
failure diagnostics survive a failed child process.

The default `--heap-measurement sampled` measures allocated Lua heap, including
reclaimable garbage. Large collection cycles can shift quarter medians even
when the live heap is stable; a sampled growth failure is not by itself proof
of a leak. To measure **retained** Lua heap explicitly, add
`--heap-measurement retained` to a sustained run. This performs one full
collection after warmup and one after the final timed acknowledgment, both
while the native application and its history are still live. It never collects
while an input is outstanding, never changes GC settings, and uses normal
collection during the measured interval. Full-history runs require full capacity
at both endpoints; increase warmup if the initial checkpoint is incomplete.

In retained mode, the same 16 MiB heap-growth gate applies to the difference
between the two post-collection heap counts. The 64 MiB sampled RSS-growth,
1 GiB peak-RSS, duration, history and two-second response gates remain unchanged.
Reports preserve all raw sampled heap values and their median growth alongside
both retained checkpoints, their pre/post heap counts, collection durations and
history occupancy. Missing endpoints, a short interval or malformed/non-finite
child evidence fail the run. The collection pauses are outside timed input
samples, so these runs do not measure the latency of an application-triggered
full collection. The application itself has no new GC policy. The method is
recorded in configuration and soak policy; comparisons across sampled and
retained modes are refused. Earlier sampled failures remain failures under their
original contract; retained mode is a distinct, explicitly selected measurement.

Visible-window measurements become `invalid` (nonzero exit) when minimized,
zero-sized or reported occluded by Metal. `--keep-visible` floats only the test
window on macOS GLFW; it cannot guarantee visibility across spaces, system UI
or display changes. Never count an invalid run as a performance pass. The pinned
[wgpu-hal 29.0.3 Metal source](https://docs.rs/crate/wgpu-hal/29.0.3/source/src/metal/surface.rs)
returns Occluded from AppKit's window occlusion state before drawable acquisition;
a failed drawable acquisition instead returns Timeout. No recovery or latency
threshold is relaxed to accommodate occlusion.

For comparable clean revisions, collect at least three independent trials per
mode with at least twenty inputs each, then run:

```sh
./script/check-interactive-budget baseline.json candidate.json
```

The checker validates raw measurements and requires matching recorded system,
runtime, actual GPU/driver/backend, container limits, font, geometry and workload.
The application, benchmarks and deterministic test runner initialize the same
finite 4 MiB LuaJIT machine-code cache ceiling. Runtime metadata records this
setting; older reports without it are incompatible for automatic comparison.
This does not enable an explicitly disabled JIT, change optimization flags or
increase the trace-count limit. The cache ceiling excludes trace metadata and
ordinary Lua heap allocations. See the [cache investigation](evidence/2026-10-27-jit-cache.md)
for both the eliminated flushes and the remaining responsiveness failures.
It refuses dirty, failed, invalid, incomplete or incompatible evidence. It compares
medians of independent trial metrics, not pooled inputs. Allowed increases are
25% or 10 ms for input p95, 25% or 50 ms for ready startup, and 10% or 32 MiB for
peak RSS (whichever allowance is larger). Exit 1 means regression; exit 2 means
comparison refused. These are initial engineering budgets, not statistical
confidence bounds. Run on an otherwise quiet, thermally stable machine; metadata
cannot establish those conditions. Shared CI runners use absolute correctness
and resource gates, not relative comparisons across unrelated machines.


### Full primary-screen history retention

The default `--scroll-mode region` leaves scrollback untouched. To qualify the
history ring and row eviction under native rendering, use:

```sh
./script/bench-interactive --mode saturated --traffic styled-unicode \
  --scroll-mode history --scrollback-limit 10000 --trials 1 \
  --samples 120 --warmup 6 --soak-seconds 600 --heap-measurement retained \
  --report /tmp/kiwi-history.json
```

History mode scrolls the full primary screen from the bottom, then repaints the
current numbered acknowledgment at the top right between lines. Repainting only
at batch boundaries can lose the marker within one PTY read, before the parent
can observe it. Retained rows include the marker in the final nine columns
alongside the background text; this is controlled fixture output. It requires saturated mode, a sustained duration and a
positive history capacity. The benchmark accepts capacities up to 100,000 rows;
this is an experiment bound, not the product configuration maximum. CI's
one-minute soaks use the default 2,000-row history capacity and explicitly select
`--heap-measurement retained` on each host. Short timing trials retain sampled
mode. Workflow configuration is not evidence of a remote CI pass.

Test-process instrumentation counts actual history pushes, returned evictions
and peak retained rows. Completion requires exactly the configured retained
capacity, at least one full capacity of evictions and consistent push accounting.
A run with insufficient output fails even if its latency samples completed.
Resource samples also record retained rows, pushes and evictions at the same
presentation points. These counts distinguish buffer filling from post-capacity
growth without changing the sampling schedule, memory gates or garbage collection.
Counters survive failed trials. The hook adds work to history-mode measurements;
compare only matching recorded scroll mode/capacity and instrumentation. Existing
resource-growth, peak-RSS, visibility and two-second response gates still apply.
Leaving the live-output viewport invalidates the measurement: matching text in
the underlying grid cannot acknowledge a frame that displays older history.

The harness regression tests drive both ASCII and styled-Unicode children through
real PTYs and replay their captured output byte by byte through the actual parser
and state. They require region scrolling to leave history empty and full-screen
scrolling to fill and replace a small bounded ring, while preserving the visible
numbered acknowledgment. They also reject incomplete/incorrect history accounting.
