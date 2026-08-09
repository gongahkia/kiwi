# Kiwi M0 and M1 component benchmarks

Run the deterministic benchmark suite with:

```sh
make bench
KIWI_BENCH_ITERATIONS=50 make bench
```

The default is 300 iterations. The command writes machine-readable schema-version-2 JSON to `bench/results/<UTC timestamp>.json`; generated results are not source-controlled. It retains M0 model/damage/packing measurements and adds M1 parser/state component measurements.

## M0 renderer-model workloads

Each M0 iteration uses the synthetic `TerminalModel`, damage tracking, contiguous range discovery, and the same 40-byte `KiwiGlyphInstance` packing used before GPU uploads. It reports CPU mean/p50/p95/p99, changed/uploaded cells, bytes, dirty ranges, full updates, and the stable three draw calls per frame at 160×50 and 240×80.

| Scenario | Purpose |
| --- | --- |
| static | populated screen with no logical changes |
| typing | 1–4 adjacent edits |
| line-churn | one full-row update |
| scrolling | synthetic content-row churn |
| full-redraw | lazy all-cells-dirty mark |

## M0 scrolling investigation

The original M0 scrolling result being slower than `full-redraw` is expected from the measured workload shape, not evidence that packing every cell is intrinsically faster. `Synthetic.apply("scrolling")` loops through content rows, constructs intermediate strings/tables, and mutates/copies each row's cells before packing. `full-redraw` only sets the lazy full-damage flag before packing. The former therefore includes substantial Lua object allocation and mutation work that the latter intentionally omits.

Representative pre-M1 M0 profiling measured scrolling mutate/range/pack costs of 0.744/0.011/0.040 ms at 160×50 and 2.028/0.027/0.228 ms at 240×80. M1 does not micro-optimise that deliberately synthetic test. Its real `Screen` scrolling shifts row references, creates entering rows only, and marks a rectangular damage range; primary scrollback is a bounded ring.

## M1 parser/state workloads

The additional workloads feed a fresh 80×24 `State` through the streaming parser each iteration:

| Workload | Stream shape |
| --- | --- |
| printable-ascii | ordinary printable output and CR/LF |
| sgr-heavy | standard, indexed, and RGB SGR output |
| cursor-erase-tui | cursor positioning, erase, ICH, and DCH |
| scrolling-newlines | long newline-heavy output into bounded history |
| mixed-captured-style | title, alternate screen, SGR, UTF-8, mode changes, and DSR |

For every workload the JSON and terminal output include bytes, actions, dirty cells/ranges, elapsed CPU percentiles, bytes per CPU second, and a cheap Lua heap-delta proxy. Heap delta is allocator-state-sensitive and is diagnostic only. Parser bytes per second is a component measurement, not input latency, render latency, GPU timing, or a cross-terminal comparison.

The benchmark is headless. It does not submit GPU work or synthesize a GPU frame time; `make smoke` is the separate native presentation correctness check. Results vary with CPU frequency, LuaJIT/JIT state, allocator state, system load, thermal conditions, and the selected iteration count.

## Representative local run

`make bench` with the default 300 iterations produced the following local component data on 2026-08-10. These values are retained as a reproducibility reference, not a cross-terminal comparison.

| M0 scenario | Grid | mean CPU update | p95 | p99 |
| --- | ---: | ---: | ---: | ---: |
| scrolling | 160×50 | 1.7304 ms | 4.3843 ms | 5.8495 ms |
| full-redraw | 160×50 | 0.0524 ms | 0.0631 ms | 0.0730 ms |
| scrolling | 240×80 | 15.4648 ms | 20.9447 ms | 22.6366 ms |
| full-redraw | 240×80 | 0.5013 ms | 0.6160 ms | 0.9012 ms |

| M1 workload | total bytes | mean parse/state | p95 | p99 | bytes/CPU second |
| --- | ---: | ---: | ---: | ---: |
| printable-ascii | 1,641,600 | 13.2149 ms | 16.9395 ms | 18.4733 ms | 414,077 |
| sgr-heavy | 1,728,000 | 9.6024 ms | 22.6227 ms | 26.7626 ms | 599,849 |
| cursor-erase-tui | 1,555,200 | 39.2198 ms | 47.3481 ms | 55.0223 ms | 132,178 |
| scrolling-newlines | 4,550,400 | 33.0351 ms | 41.3251 ms | 51.2209 ms | 459,148 |
| mixed-captured-style | 2,361,600 | 53.5484 ms | 61.3316 ms | 69.0994 ms | 147,007 |
