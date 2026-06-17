# @docusaurus/plugin-kumeyuri

Docusaurus plugin that injects the kumeyuri browser player so MDX pages can use
`<kumeyuri-diagram>`.

```js
export default {
  plugins: [
    [
      "@docusaurus/plugin-kumeyuri",
      {
        scriptUrl: "https://cdn.kumeyuri.dev/player.js",
        preload: true,
      },
    ],
  ],
};
```

Use generated assets with normal Markdown:

```md
![Request flow](/diagrams/flow.svg)
```

Or use the browser player in MDX after the plugin injects the player module:

```mdx
<kumeyuri-diagram
  src="/diagrams/flow.mmd"
  animate="trace"
  theme="github"
  controls
/>
```

Options:

| Option | Default | Purpose |
| --- | --- | --- |
| `inject` | `true` | Inject the player module script. |
| `preload` | `false` | Add a `modulepreload` link for the player. |
| `scriptUrl` | `https://cdn.kumeyuri.dev/player.js` | Browser player module URL. |
| `integrity` | unset | Optional subresource integrity value. |
| `crossorigin` | unset | Optional `crossorigin` script/link attribute. |
