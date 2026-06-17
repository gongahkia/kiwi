# rehype-kumeyuri

Rehype plugin that renders Mermaid code blocks with `kumeyuri`.

It looks for HAST nodes shaped like:

```html
<pre><code class="language-mermaid">graph TD...</code></pre>
```

By default it appends rendered SVG after the source block.

## Usage

```js
import rehypeKumeyuri from "rehype-kumeyuri"

processor.use(rehypeKumeyuri, {
  format: "svg",
  kumeyuri: "kumeyuri",
})
```

For SVG output, use `rehype-stringify` with `allowDangerousHtml: true` or run `rehype-raw` after this plugin so the raw SVG node is emitted.

Options:

- `format`: `svg` or `text`, default `svg`.
- `kumeyuri`: binary path, default `kumeyuri`.
- `replace`: replace the Mermaid source block instead of appending output.
- `theme`, `darkTheme`, `charset`, `width`, `padding`, `font`: forwarded to `kumeyuri render`.
