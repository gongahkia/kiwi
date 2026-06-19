# Docusaurus

`packages/docusaurus-plugin-kumeyuri` injects the browser player so MDX can use
`<kumeyuri-diagram>`.

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

```mdx
<kumeyuri-diagram src="/diagrams/flow.mmd" animate="trace" theme="github" controls />
```

Use normal Markdown image links for pre-rendered SVG/GIF/APNG/WebP assets.
