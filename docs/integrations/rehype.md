# rehype

`packages/rehype-kumeyuri` renders HAST Mermaid code blocks by invoking the
`kumeyuri` binary.

```js
import rehypeKumeyuri from "rehype-kumeyuri";

processor.use(rehypeKumeyuri, {
  format: "svg",
  kumeyuri: "kumeyuri",
});
```

For SVG output, configure the downstream HTML compiler to allow raw HTML or run
`rehype-raw` where that pipeline requires it.
