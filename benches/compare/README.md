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
