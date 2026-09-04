# Comparison Benchmark Corpus

This directory contains source inputs shared by the comparison harnesses.
Each tool adapter should read from `corpus/manifest.json` and write outputs under
an ignored results directory, not mutate these inputs.

The corpus intentionally mixes simple and feature-heavy diagrams. Keep files
small enough for fast CI runs, but representative enough to catch parser,
layout, renderer, and output-size differences.

Rules:

* Add only Mermaid source files under `corpus/`.
* Update `corpus/manifest.json` whenever a source file is added, removed, or
  renamed.
* Prefer inputs copied from first-party fixtures or examples so expected
  behavior is already covered elsewhere.
* Do not add generated SVG, raster, or text outputs here.

Adapters:

* `npm run bench:compare:beautiful-mermaid` renders the manifest through
  `beautiful-mermaid@1.1.3` via `benches/compare/tools/beautiful-mermaid.mjs`
  and writes generated text/error outputs under `benches/compare/results/`.
  Current upstream support is limited to flowchart, state, sequence, class, ER,
  and XY chart inputs, so unsupported corpus roots are recorded as adapter
  errors rather than committed fixtures.
* `npm run bench:compare:alexander-mermaid-ascii` renders the manifest through
  the `AlexanderGrooff/mermaid-ascii` Go CLI. Install the binary separately and
  expose it on `PATH`, or set `MERMAID_ASCII_BIN=/path/to/mermaid-ascii`.
  The adapter invokes `mermaid-ascii --file <input> --ascii` and records
  nonzero exits as per-input errors.
* `npm run bench:compare:pgavlin-mermaid-ascii` renders the manifest through
  the `pgavlin/mermaid-ascii` Go CLI. Install that fork separately and expose
  it on `PATH`, or set `PGAVLIN_MERMAID_ASCII_BIN=/path/to/mermaid-ascii`.
  The adapter invokes `mermaid-ascii --file <input> --ascii` and records
  nonzero exits as per-input errors.
* `npm run bench:compare:mermaid2term` renders the manifest through
  `mermaid2term@0.1.0` via `benches/compare/tools/mermaid2term.mjs`. The
  adapter invokes the local npm binary as `mermaid2term --ascii <input>` and
  records nonzero exits as per-input errors.
* `npm run bench:compare:mermaid-cli` renders ground-truth SVGs through
  `@mermaid-js/mermaid-cli@11.15.0` via `benches/compare/tools/mermaid-cli.mjs`.
  The adapter invokes the local `mmdc` binary with headless Puppeteer and writes
  SVG outputs under `benches/compare/results/mermaid-cli/`.
* `npm run bench:compare:output-size` measures generated output size for each
  adapter result under `benches/compare/results/`, reporting bytes, characters,
  and line counts for successful outputs while preserving missing/error states.
* `npm run bench:compare:results` writes the same aggregate payload to
  `bench/results.json` for downstream publishing jobs.
* `npm run bench:compare:timing` runs `hyperfine` against available adapters for
  one corpus input and writes the JSON export under
  `benches/compare/results/timing.json`. Set `MERMAID_ASCII_BIN` and
  `PGAVLIN_MERMAID_ASCII_BIN` to include external Go adapters.
* `npm run bench:compare:fidelity` scores text adapters against `mermaid-cli`
  SVG ground truth by extracting visible SVG labels and measuring label recall.
  This is a conservative semantic smoke score, not a pixel/image diff.

## Release benchmark workflow

`kumeyuri` now has a comparison adapter and a release-only phase probe. Prepare
both release binaries once before invoking either directly:

```sh
npm run bench:compare:prepare
```

The adapter at `tools/kumeyuri.mjs` defaults to `target/release/kumeyuri` and
never invokes `cargo run`. Override the binary with `KUMEYURI_BENCH_BIN` or
`--bin` when profiling a separately built artifact.

```sh
npm run bench:compare:kumeyuri -- --input benches/compare/corpus/flowchart-dense.mmd --stdout
npm run bench:compare:timing -- --input benches/compare/corpus/scales/flowchart-tree-100.mmd --runs 10
```

The timing command compares process-level wall time through Hyperfine. It now
includes KumeYuri alongside the existing adapters, but each tool's output model
remains different and the comparison should not be read as visual-fidelity
evidence.

## Generated scale corpus

`corpus/scales/` is generated, checked-in input—not ephemeral benchmark output.
It contains:

* 10, 50, 100, 250, and 500 node flowcharts for chains, trees, fan-in, fan-out,
  cycles, and nested subgraphs with long labels;
* 5/100, 10/250, and 20/500 participant/message sequence workloads with
  activations and nested `loop`/`alt`/`critical` blocks; and
* state hierarchies nested 5, 10, and 20 levels deep.

Regenerate after changing `tools/generate-scale-corpus.mjs`; CI-oriented checks
must use `--check` instead:

```sh
node benches/compare/tools/generate-scale-corpus.mjs --write
npm run test:bench:scale-corpus
```

`corpus/manifest.json` stays a fast, feature-focused corpus. The generated
`corpus/benchmark-manifest.json` combines it with every scale fixture and is
the default for phase and SVG-structure reports.

Large animated sources can legitimately consume substantial time and memory:
each trace frame carries a complete text grid. Do not put every output phase
for the 500-node fixtures in routine unit-test CI. Select an input and phase
when investigating a regression.

## Phase measurements

`kumeyuri-bench` measures individual operations inside a release process:

| Operation | Scope |
| --- | --- |
| `parse` | Mermaid source to KumeYuri AST |
| `layout` | Isolated layout for flowchart, sequence, and state roots |
| `frames` | Animated timeline and text-frame generation |
| `svg` | SVG serialization from a prebuilt timeline |
| `kumecast` | KumeCast JSON serialization from a prebuilt timeline |
| `raster-gif`, `raster-apng`, `raster-webp` | GIF, APNG, and WebP encoding from a prebuilt timeline |

The Node runner records every measured sample, p50/p95/min/max milliseconds,
and Linux peak RSS from `/usr/bin/time`. Each isolated probe runs in a user
systemd scope with a 4 GiB memory limit, no swap, and a five-minute wall-time
limit. Override either with `--memory-max-mib` or `--timeout-seconds`. Setup
work is intentionally outside the component sample, while peak RSS covers the
whole probe process.

```sh
npm run bench:compare:phases -- \
  --input benches/compare/corpus/scales/flowchart-tree-100.mmd \
  --iterations 20 --warmup 3
```

The default command writes ignored JSON beneath `benches/compare/results/`.
Use `--allow-failures` to retain results for intentionally capacity-breaking
inputs without making the command fail.

## Structural SVG comparison

Render the same pinned benchmark manifest through both KumeYuri and Mermaid
CLI, then compare accessible text, SVG element counts, viewbox metadata, and
semantic element classes:

```sh
npm run bench:compare:svg
```

`tools/compare-svg-structure.mjs` writes `svg-structure.json`. Its label
metrics are retained for continuity, but the report also captures tag-count and
element-count differences plus accessibility metadata. It deliberately does
not declare a visual match: KumeYuri renders text-grid SVG while Mermaid CLI
uses a browser SVG layout. Screenshot/image diffs remain an optional stronger
visual gate for a future renderer whose geometry is intended to match Mermaid.
