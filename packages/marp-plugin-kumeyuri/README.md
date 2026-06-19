# @kumeyuri/marp-plugin

Marp CLI engine hook for embedding `.kumecast` timelines in Marp slides.

Create an engine file:

```js
import kumeyuri from "@kumeyuri/marp-plugin";

export default (context) =>
  kumeyuri(context, {
    scriptUrl: "./kumeyuri-reveal.js",
    autoplay: true,
  });
```

Run Marp CLI with the engine:

```bash
marp --engine ./engine.mjs slides.md --html
```

Use a `kumecast` fence in a slide:

````md
```kumecast
./casts/oauth-login.kumecast
```
````

The hook rewrites the fence to:

```html
<div class="kumeyuri-marp-cast" data-kumeyuri-cast="./casts/oauth-login.kumecast" data-controls></div>
```

Options:

| Option | Default | Purpose |
| --- | --- | --- |
| `className` | `kumeyuri-marp-cast` | Class for generated placeholders |
| `autoplay` | `false` | Add `data-autoplay` |
| `controls` | `true` | Add `data-controls` |
| `loop` | `false` | Add `data-loop` |
| `scriptUrl` | unset | Optional module script URL to append beside each placeholder |

Pair the output with `@kumeyuri/reveal-plugin` or a compatible runtime that
loads `[data-kumeyuri-cast]` elements.
