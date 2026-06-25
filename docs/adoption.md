# Adoption

Use [`docs/book/adoption.md`](book/adoption.md) as the source checklist for real
website adoption.

Covered surfaces:

- single-install browser package via `kumeyuri/wasm`;
- GitHub Pages landing site under `site/`;
- live playground with copyable embeds and SVG download;
- `kumeyuri compat --json` for machine-readable support;
- line/column parse diagnostics;
- runtime hardening with `max-source-bytes`, `fetch-timeout-ms`, `lazy`, and `csp`;
- distribution trust checks and `site/integrity.json`;
- adoption gallery;
- animation intent by diagram family;
- static-first framework plugins;
- regression dashboard data in `site/status.json`.

Verification:

```bash
npm run site:verify
npm run integrity:site:check
npm run test:ts-package
npm run test:web-component:browsers
npm run test:web-component:a11y
npm run test:web-component:keyboard
npm run test:web-component:touch-targets
npm run test:web-component:perf
```
