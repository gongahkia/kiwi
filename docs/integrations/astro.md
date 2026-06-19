# Astro

`packages/astro` injects the browser player into Astro pages.

```js
import { defineConfig } from "astro/config";
import kumeyuri from "@kumeyuri/astro";

export default defineConfig({
  integrations: [
    kumeyuri({
      scriptUrl: "/kumeyuri/player.js",
    }),
  ],
});
```

Use generated assets with Markdown, or use `<kumeyuri-diagram>` in `.astro` and
MDX content.
