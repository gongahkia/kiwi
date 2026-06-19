# quartz-plugin-kumeyuri

Quartz transformer plugin for embedding `.kumecast` timelines in a digital
garden.

Add it to `quartz.config.ts`:

```ts
import Kumeyuri from "quartz-plugin-kumeyuri";

export default {
  plugins: {
    transformers: [
      Kumeyuri({
        scriptUrl: "https://cdn.kumeyuri.dev/player.js",
      }),
    ],
  },
};
```

Use a `kumecast` fence:

````md
```kumecast
/casts/oauth-login.kumecast
```
````

The transformer rewrites the fence to:

```html
<div class="kumeyuri-quartz-cast" data-kumeyuri-cast="/casts/oauth-login.kumecast" data-controls="true"></div>
```

Options:

| Option | Default | Purpose |
| --- | --- | --- |
| `className` | `kumeyuri-quartz-cast` | Placeholder class |
| `autoplay` | `false` | Add `data-autoplay` |
| `controls` | `true` | Add `data-controls` |
| `loop` | `false` | Add `data-loop` |
| `scriptUrl` | `https://cdn.kumeyuri.dev/player.js` | Client player module URL |
| `cssUrl` | empty | Optional CSS URL |
