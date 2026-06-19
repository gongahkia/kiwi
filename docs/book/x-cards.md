# X Cards

X link previews use Twitter Card metadata names. For kumeyuri diagrams, prefer a
static PNG, WebP, or GIF card image over live WASM embeds because social crawlers
do not execute the player.

## Generate a card image

Use a raster output for the card image:

```sh
kumeyuri render diagrams/launch.mmd \
  --format webp \
  --theme github \
  --padding 24 \
  > public/cards/launch.webp
```

Use SVG for the page body when the host allows it, but use raster for the card
image so the crawler receives a plain image asset.

## Metadata

Add card and Open Graph metadata to the page `<head>`:

```html
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Kumeyuri launch">
<meta name="twitter:description" content="Animated Mermaid diagrams from one frame stream.">
<meta name="twitter:image" content="https://kumeyuri.dev/cards/launch.webp">

<meta property="og:title" content="Kumeyuri launch">
<meta property="og:description" content="Animated Mermaid diagrams from one frame stream.">
<meta property="og:image" content="https://kumeyuri.dev/cards/launch.webp">
<meta property="og:url" content="https://kumeyuri.dev/blog/launch.html">
```

Use absolute HTTPS URLs for image and page URLs. Relative paths are unreliable
for social crawlers.

## Image constraints

Use a large-image card when the diagram is visual enough to sell the page:

| Field | Recommendation |
| --- | --- |
| Aspect ratio | 2:1 crop-safe layout |
| Width | 1200 px target |
| Height | 600 px target |
| Format | PNG, WebP, JPG, or GIF |
| File size | Keep comfortably below 5 MB |

Keep key text away from edges because clients may crop differently.

## Diagram-specific checklist

- Render a dedicated card asset; do not reuse a tiny README badge.
- Use `github` or another light theme unless the page itself is dark-first.
- Prefer `--padding 24` or higher so connectors do not touch the crop edge.
- Put the product/page title in HTML metadata, not inside the diagram only.
- Re-fetch or re-share the URL after changing metadata; card caches can lag.
