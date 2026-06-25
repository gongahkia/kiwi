# Security and Production Embeds

kumeyuri does not embed Mermaid.js and does not execute Mermaid `click`
callbacks. Treat diagram source, fetched files, and surrounding CMS/MDX HTML as
untrusted input anyway.

## Recommended Embed Shape

Use generated assets for public content that does not need runtime controls:

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

Use the web component when source loading, playback controls, or client-side
theme/runtime selection are required:

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

## Source Policy

- Prefer same-origin `src` URLs under a known diagrams directory.
- Do not pass arbitrary user-provided URLs into `src`.
- If users can author Mermaid, validate on write with `kumeyuri lint` or
  `kumeyuri render --format svg` and store the generated asset.
- Keep fallback HTML authored by trusted templates; sanitize CMS/user HTML before
  it reaches `<kumeyuri-diagram>`.

## CSP Mode

Set `csp` when inline style attributes are blocked. Provide page CSS for the
parts:

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

## Operational Checks

Before shipping a site integration:

```bash
npm run test:web-component:browsers
npm run test:web-component:a11y
npm run test:web-component:keyboard
npm run test:web-component:touch-targets
npm run test:web-component:perf
scripts/check-wasm-budget.sh
```

Use `kumeyuri compat` to confirm whether each diagram family is animated,
static-only, or outside the tracked compatibility surface.
