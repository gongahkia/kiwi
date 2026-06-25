# Web Embed Security

kumeyuri browser embeds do not execute Mermaid `click` callbacks and do not load
Mermaid.js. Still treat Mermaid source, fetched diagram files, and surrounding
CMS/MDX HTML as untrusted input.

## Default Production Path

Prefer pre-rendered assets when a site does not need runtime controls:

```bash
kumeyuri render diagrams/flow.mmd --format svg --theme github --dark-theme tokyo-night > public/diagrams/flow.svg
kumeyuri render diagrams/flow.mmd --format webp --theme github > public/diagrams/flow.webp
```

```html
<picture>
  <source srcset="/diagrams/flow.webp" type="image/webp">
  <img src="/diagrams/flow.svg" alt="Request flow">
</picture>
```

Use `<kumeyuri-diagram>` when client-side source loading, playback controls, or
runtime options matter:

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

## Source Rules

- Keep `src` same-origin and scoped to a known diagrams directory.
- Do not pass arbitrary user-provided URLs to `src`.
- Validate user-authored Mermaid before publish with `kumeyuri lint` or
  `kumeyuri render --format svg`; scan migrations with `kumeyuri audit-mermaid`.
- Sanitize user-authored HTML outside kumeyuri before it reaches MDX/CMS output.

## CSP

Set the `csp` attribute to avoid inline control styles. Then style exposed parts
from site CSS:

```css
kumeyuri-diagram[csp] { position: relative; }
kumeyuri-diagram [part="controls"] {
  position: absolute;
  right: .5rem;
  bottom: .5rem;
  display: flex;
  gap: .25rem;
}
kumeyuri-diagram [part="play-button"],
kumeyuri-diagram [part="restart-button"],
kumeyuri-diagram [part="scrubber"] {
  min-height: 44px;
}
```

For a static site, start with this policy and tighten it around your own asset
paths:

```http
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'
```

## SRI and Pinned Assets

Use `site/integrity.json` to pin checked-in browser files:

```html
<script
  type="module"
  src="/pkg/kumeyuri_render_wasm.js"
  integrity="sha384-Th8ISiYUbgAB2kJdO/e1iOeh0H+Rk1g0dGaZgpFrsas1wfYpPmFlFyJO+d5Yzj7F"
  crossorigin="anonymous"
></script>
```

Regenerate and verify hashes whenever the WASM package changes:

```bash
npm run integrity:site
npm run integrity:site:check
```

If a host lets users submit arbitrary HTML around diagrams, enforce Trusted
Types at the host application boundary and sanitize that HTML before it reaches
MDX/CMS output. kumeyuri does not make surrounding CMS HTML safe.

## Verification

```bash
npm run test:web-component:browsers
npm run test:web-component:a11y
npm run test:web-component:keyboard
npm run test:web-component:touch-targets
npm run test:web-component:perf
scripts/check-wasm-budget.sh
```
