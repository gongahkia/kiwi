# Adoption Playbook

This page is the release checklist for making kumeyuri practical on real
websites.

## 1. Single-Install Browser Package

The npm package exports both the wrapper and the wasm-bindgen module:

```bash
npm install kumeyuri
```

```ts
import initWasm, * as wasm from "kumeyuri/wasm";
import { defineKumeyuriElement, initKumeyuri } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });
defineKumeyuriElement();
```

Use `kumeyuri/react` for React apps and the same `kumeyuri/wasm` module for
initialization.

## 2. Landing Page and Playground

The GitHub Pages landing site lives under `site/`. It includes install commands,
a live WASM playground, copyable embed snippets, SVG download, compatibility
warnings, adoption gallery, distribution trust notes, and a regression dashboard.

Local verification:

```bash
npm run site:verify
```

## 3. Machine-Readable Compatibility

Use JSON output for docs, agents, release notes, and site warnings:

```bash
kumeyuri compat --json
```

The static landing page keeps a checked-in `site/compat.json`; `npm run
site:verify` fails if it drifts from the CLI.

## 4. Parse Diagnostics

CLI and WASM parse errors include byte span, line, column, source line, caret,
and targeted suggestions for unsupported Mermaid config or unknown roots.

## 5. Runtime Embed Hardening

Production live embeds should set conservative limits:

```html
<kumeyuri-diagram
  src="/diagrams/flow.mmd"
  animate="trace"
  controls
  csp
  lazy
  max-source-bytes="200000"
  fetch-timeout-ms="5000"
>
  <svg role="img" aria-label="Request flow fallback"></svg>
  <noscript><img src="/diagrams/flow.svg" alt="Request flow"></noscript>
</kumeyuri-diagram>
```

Defaults are `max-source-bytes="1000000"` and `fetch-timeout-ms="10000"`.

## 6. Distribution Trust

Before publishing:

```bash
npm pack --dry-run
npm run integrity:site
cargo audit
cargo deny check
scripts/check-wasm-budget.sh
shasum -a 256 site/pkg/* packages/kumeyuri/wasm/*
```

Release artifacts should include npm provenance, checksums, SBOM output, and SRI
hashes for static browser assets. `site/integrity.json` records SHA-256 and SRI
hashes for checked-in browser assets; `npm run site:verify` fails if it drifts.

## 7. Adoption Gallery

The landing page gallery shows API docs, architecture pages, and teaching posts.
Each gallery item includes the source command that produced the asset.

## 8. Animation Polish

Animated families should explain diagram semantics, not just prove multiple
frames exist:

| Family | Animation intent |
| --- | --- |
| Flowchart, class, ER, mindmap, journey, gitGraph, timeline | Reveal structure in source or dependency order. |
| Sequence | Play messages over participant lanes. |
| State | Step transitions between states. |
| Gantt | Trace scheduled work over a day-level timeline. |
| Pie | Reveal slices and value proportions. |

Static-only families must still render useful, deterministic schematics.

## 9. Static-First Framework Plugins

Prefer build-time rendering for content sites:

| Surface | Path |
| --- | --- |
| Markdown/MDX | `remark-kumeyuri`, `rehype-kumeyuri` |
| Docusaurus | `@docusaurus/plugin-kumeyuri` |
| Astro | `@kumeyuri/astro` |
| mdBook | `mdbook-kumeyuri` |
| GitHub CI | `render-action/` |

Ship the WASM component only on pages that need runtime source loading or
interactive playback.

## 10. Regression Dashboard

The landing site reads `site/status.json`. Keep it aligned with:

- compatibility counts from `kumeyuri compat --json`;
- WASM gzip budget from `scripts/check-wasm-budget.sh`;
- browser matrix from `npm run test:web-component:browsers`;
- web performance budget from `npm run test:web-component:perf`.
