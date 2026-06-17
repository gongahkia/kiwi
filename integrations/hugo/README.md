# Hugo shortcode

Copy `layouts/shortcodes/kumeyuri.html` into a Hugo site.

Render diagrams into Hugo's `static/` tree:

```bash
kumeyuri render diagrams/flow.mmd --format svg --theme github > static/diagrams/flow.svg
kumeyuri render diagrams/flow.mmd --format svg --theme github --dark-theme tokyo-night > static/diagrams/flow.dark.svg
```

Use the shortcode in Markdown:

```md
{{< kumeyuri src="/diagrams/flow.svg" dark="/diagrams/flow.dark.svg" alt="Animated flow trace" caption="Request flow" >}}
```

Supported params:

| Param | Required | Purpose |
| --- | --- | --- |
| `src` | yes | Light/default SVG, GIF, APNG, or WebP URL. |
| `dark` / `darkSrc` | no | Dark-mode asset URL via `prefers-color-scheme: dark`. |
| `alt` | no | Image alt text; falls back to `caption`, then `Kumeyuri diagram`. |
| `caption` | no | Optional `<figcaption>`. |
| `class` | no | Extra class appended to `kumeyuri-diagram`. |
| `width` / `height` | no | Image dimensions. |
| `loading` | no | Image loading mode; defaults to `lazy`. |
| `decoding` | no | Image decoding mode; defaults to `async`. |
