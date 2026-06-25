# Static Site Recipes

Prefer static assets for public websites. Use the WASM player only where users
need runtime controls, source loading, or live editing.

## Plain HTML / GitHub Pages

```bash
mkdir -p site/diagrams
kumeyuri render diagrams/request.mmd --format svg --theme github --dark-theme tokyo-night > site/diagrams/request.svg
kumeyuri render diagrams/request.mmd --format webp --theme github > site/diagrams/request.webp
kumeyuri compat --json > site/kumeyuri-compat.json
kumeyuri audit-mermaid ./docs --json > site/kumeyuri-audit.json
```

```html
<picture>
  <source srcset="/diagrams/request.webp" type="image/webp">
  <img src="/diagrams/request.svg" alt="Request flow">
</picture>
```

## Docusaurus

```js
export default {
  plugins: [
    [
      "@docusaurus/plugin-kumeyuri",
      {
        scriptUrl: "/kumeyuri/player.js",
        preload: true,
      },
    ],
  ],
};
```

Use static SVG/WebP in ordinary docs pages and `<kumeyuri-diagram>` only for
interactive pages.

## Astro

```js
import kumeyuri from "@kumeyuri/astro";

export default {
  integrations: [kumeyuri({ scriptUrl: "/kumeyuri/player.js" })],
};
```

## mdBook

```toml
[preprocessor.kumeyuri]
command = "mdbook-kumeyuri"
format = "svg"
theme = "github"
```

## Markdown / MDX

Use `remark-kumeyuri` before HTML generation or `rehype-kumeyuri` after Markdown
has been parsed to HAST. Keep generated assets committed or cached in CI for
reproducible builds.
