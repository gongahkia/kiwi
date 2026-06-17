# @kumeyuri/astro

Astro integration that injects the kumeyuri browser player on every page.

```js
import { defineConfig } from "astro/config";
import kumeyuri from "@kumeyuri/astro";

export default defineConfig({
  integrations: [
    kumeyuri({
      scriptUrl: "https://cdn.kumeyuri.dev/player.js",
    }),
  ],
});
```

Use generated assets with normal Markdown:

```md
![Request flow](/diagrams/flow.svg)
```

Or use the browser player in `.astro` or MDX content:

```html
<kumeyuri-diagram src="/diagrams/flow.mmd" animate="trace" theme="github" controls></kumeyuri-diagram>
```

Options:

| Option | Default | Purpose |
| --- | --- | --- |
| `inject` | `true` | Inject the player import. |
| `scriptUrl` | `https://cdn.kumeyuri.dev/player.js` | Browser player module URL. |
| `stage` | `head-inline` | Astro `injectScript` stage: `head-inline`, `before-hydration`, or `page`. |
