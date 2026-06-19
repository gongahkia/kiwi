# @kumeyuri/reveal-plugin

reveal.js plugin that loads `.kumecast` JSON timelines inline in slides.

```js
import Reveal from "reveal.js";
import Kumeyuri from "@kumeyuri/reveal-plugin";

const deck = new Reveal({
  plugins: [Kumeyuri({ autoplay: true })],
});

deck.initialize();
```

Add cast placeholders to slides:

```html
<section>
  <div data-kumeyuri-cast="/casts/oauth-login.kumecast" data-autoplay></div>
</section>
```

Options:

| Option | Default | Purpose |
| --- | --- | --- |
| `selector` | `[data-kumeyuri-cast]` | Elements to replace with cast players |
| `autoplay` | `false` | Start playback after loading |
| `controls` | `true` | Render play/restart/scrub controls |
| `loop` | `false` | Loop playback even when the cast does not repeat |
| `fetcher` | `globalThis.fetch` | Test/custom fetch implementation |

The plugin follows the reveal.js plugin API: it exports a function that returns
an object with `id`, `init(deck)`, and `destroy()`.
