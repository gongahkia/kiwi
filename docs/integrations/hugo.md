# Hugo

`integrations/hugo/` provides a shortcode for static generated assets.

Copy the shortcode into a Hugo site:

```sh
mkdir -p layouts/shortcodes
cp integrations/hugo/layouts/shortcodes/kumeyuri.html layouts/shortcodes/
```

Render assets into Hugo's `static/` tree:

```sh
kumeyuri render diagrams/flow.mmd --format svg --theme github > static/diagrams/flow.svg
kumeyuri render diagrams/flow.mmd --format svg --theme github --dark-theme tokyo-night > static/diagrams/flow.dark.svg
```

Use it from Markdown:

```md
{{< kumeyuri src="/diagrams/flow.svg" dark="/diagrams/flow.dark.svg" alt="Animated flow trace" caption="Request flow" >}}
```
