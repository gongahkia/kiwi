# remark-kumeyuri

Remark plugin that renders Mermaid code blocks with `kumeyuri`.

It looks for MDAST code nodes such as:

````markdown
```mermaid
graph TD
  A --> B
```
````

By default it appends rendered SVG after the source block as an HTML node.

## Usage

```js
import remarkKumeyuri from "remark-kumeyuri"

processor.use(remarkKumeyuri, {
  format: "svg",
  kumeyuri: "kumeyuri",
})
```

For SVG output, use a Markdown compiler that allows HTML output. For pipelines
that continue through rehype, use `rehype-raw` only if your downstream compiler
requires raw HTML nodes to be reparsed.

Options:

- `format`: `svg` or `text`, default `svg`.
- `kumeyuri`: binary path, default `kumeyuri`.
- `replace`: replace the Mermaid source block instead of appending output.
- `theme`, `darkTheme`, `charset`, `width`, `padding`, `font`: forwarded to `kumeyuri render`.
