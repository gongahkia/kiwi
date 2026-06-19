# Comparison Benchmark Corpus

This directory contains source inputs shared by future comparison harnesses.
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
