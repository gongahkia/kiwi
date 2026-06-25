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
  `kumeyuri render --format svg`.
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

## Verification

```bash
npm run test:web-component:browsers
npm run test:web-component:a11y
npm run test:web-component:keyboard
npm run test:web-component:touch-targets
npm run test:web-component:perf
scripts/check-wasm-budget.sh
```
