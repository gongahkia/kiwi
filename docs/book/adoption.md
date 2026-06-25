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

The public dashboard also ships `site/parity.json` and `site/motion.json`.
`site/parity.json` compares the 31 official-corpus fixtures against both
Mermaid CLI and kumeyuri; `site/motion.json` checks animation frame counts,
durations, SVG animation mode, and reduced-motion CSS.

```bash
npm run test:mermaid-parity
npm run test:animation-quality
```

## 4. Parse Diagnostics

CLI and WASM parse errors include byte span, line, column, source line, caret,
and targeted suggestions for unsupported Mermaid config or unknown roots.

## 5. Migration Audit

Run this before replacing Mermaid.js on an existing site:

```bash
kumeyuri audit-mermaid ./docs ./site/content --json > kumeyuri-audit.json
```

The audit reports parsed/rendered status, support class, frame count, ignored
Mermaid config, and migration suggestions for each `.mmd`, `.mermaid`, Markdown,
or MDX Mermaid source.

## 6. Runtime Embed Hardening

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

For public sites, pin static player files with SRI from `site/integrity.json`
and keep `src` same-origin. Use CSP with `script-src 'self'` for static assets
or explicit hashes/nonces if your integration inlines scripts.

## 7. Distribution Trust

Before publishing:

```bash
npm pack --dry-run
npm run integrity:site
npm run release:trust
cargo audit
cargo deny check
scripts/check-wasm-budget.sh
shasum -a 256 site/pkg/* packages/kumeyuri/wasm/*
```

Release artifacts should include npm provenance, checksums, SBOM output, and SRI
hashes for static browser assets. `site/integrity.json` records SHA-256 and SRI
hashes for checked-in browser assets; `npm run site:verify` fails if it drifts.

## 8. Adoption Gallery

The landing page gallery shows API docs, architecture pages, and teaching posts.
Each gallery item includes the source command that produced the asset.

## 9. Animation Polish

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

## 10. Static-First Framework Plugins

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

See [Static Site Recipes](static-site-recipes.md) for GitHub Pages, Docusaurus,
Astro, mdBook, Markdown, and MDX examples.

## 11. Regression Dashboard

The landing site reads `site/status.json`. Keep it aligned with:

- compatibility counts from `kumeyuri compat --json`;
- parity counts from `site/parity.json`;
- animation quality counts from `site/motion.json`;
- WASM gzip budget from `scripts/check-wasm-budget.sh`;
- release-trust checks from `npm run release:trust`;
- browser matrix from `npm run test:web-component:browsers`;
- web performance budget from `npm run test:web-component:perf`.
