# remark

`packages/remark-kumeyuri` renders MDAST Mermaid code blocks by invoking the
`kumeyuri` binary.

```js
import remarkKumeyuri from "remark-kumeyuri";

processor.use(remarkKumeyuri, {
  format: "svg",
  kumeyuri: "kumeyuri",
});
```

Use `replace: true` to replace source fences; leave it unset to append rendered
output after each source fence.
