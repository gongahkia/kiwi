# M0 benchmarks

Run the deterministic benchmark suite with:

```sh
make bench
```

The command runs 300 iterations by default; set `KIWI_BENCH_ITERATIONS` to control that count. It writes a machine-readable result to `bench/results/<UTC timestamp>.json` and prints matching human-readable rows. `bench/results/example.json` documents the schema shape without claiming machine results.

## What it measures

Each iteration uses a real `TerminalModel`, synthetic mutation scenario, sparse/full damage state, contiguous-range discovery, and `KiwiGlyphInstance` packing. It records CPU update time, changed cells, cells/bytes that the renderer would upload, range count, full-update count, and the stable M0 three-draw-call render graph.

The suite runs every scenario at 160×50 and 240×80:

| Scenario | Workload | Purpose |
| --- | --- | --- |
| static | populated screen, no logical changes | baseline/no unnecessary uploads |
| typing | 1–4 adjacent cell edits | sparse damage and tiny staging |
| line-churn | one complete row | medium contiguous range |
| scrolling | substantial content-row churn | common terminal stress shape |
| full-redraw | lazy all-cells-dirty mark | upper update bound |

Percentiles use sorted samples and linear interpolation: p50/p95/p99 are CPU update-time percentiles in milliseconds.

## What it does not measure

The default harness is headless, so it does not submit GPU work, estimate end-to-end input latency, or claim GPU frame time. It declares GPU timing unsupported rather than inventing it. `make smoke` separately exercises actual Vulkan presentation; that is a correctness check, not a performance benchmark.

Results vary with CPU frequency policy, LuaJIT version/JIT warm-up, allocator state, compositor load, font choice, thermal state, and background processes. Compare runs from the same machine and command shape. M0 makes no cross-terminal performance claim.
