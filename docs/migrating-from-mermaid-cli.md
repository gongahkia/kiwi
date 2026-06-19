# Migrating from mermaid-cli

`@mermaid-js/mermaid-cli` provides `mmdc`, a Node/Chromium CLI that renders
Mermaid source to SVG, PNG, PDF, and transformed Markdown. kumeyuri provides a
Rust CLI and renderer stack focused on deterministic frames, terminal playback,
animated SVG, raster formats, and WASM embeds.

## Main differences

| Area | mermaid-cli | kumeyuri |
| --- | --- | --- |
| Binary | `mmdc` | `kumeyuri` |
| Runtime | Node + Chromium/Puppeteer | Rust CLI; browser only for WASM embed tests |
| SVG | Mermaid-rendered SVG | Text-frame SVG with SMIL or CSS-keyframe animation |
| Raster | PNG via browser rendering | GIF/APNG/WebP via frame timeline |
| PDF | Built-in output target | Tracked as plugin work in `TODO.md` |
| Markdown transform | Built into `mmdc` | Use remark/rehype/mdBook/Hugo integrations |

## CLI replacement

Before:

```sh
mmdc -i diagram.mmd -o diagram.svg
```

After:

```sh
kumeyuri render diagram.mmd --format svg --theme github > diagram.svg
```

Use explicit formats:

```sh
kumeyuri render diagram.mmd --format text > diagram.txt
kumeyuri render diagram.mmd --format gif --padding 12 > diagram.gif
kumeyuri render diagram.mmd --format apng --padding 12 > diagram.png
kumeyuri render diagram.mmd --format webp --padding 12 > diagram.webp
```

## Theme migration

Before:

```sh
mmdc -i input.mmd -o output.png -t dark -b transparent
```

After:

```sh
kumeyuri render input.mmd --format svg --theme tokyo-night > output.svg
kumeyuri render input.mmd --format svg --theme github --dark-theme tokyo-night > output.svg
```

kumeyuri does not currently expose Mermaid's full theme/config surface. Use
`docs/book/themes.md` for supported built-in themes and `COVERAGE.md` for config
parity notes.

## Markdown pipelines

`mmdc` can transform Markdown and replace Mermaid fences with generated images.
In kumeyuri, choose the integration that matches the host:

| Host | Integration |
| --- | --- |
| unified/HTML | `rehype-kumeyuri` |
| unified/Markdown | `remark-kumeyuri` |
| mdBook | `mdbook-kumeyuri` |
| Hugo | `integrations/hugo` shortcode |
| Docusaurus | `@docusaurus/plugin-kumeyuri` |
| Astro | `@kumeyuri/astro` |

See `docs/integrations/` for setup notes.

## Browser and CI dependencies

mermaid-cli needs a browser runtime. The comparison adapter in this repo uses
Playwright Chromium when `MERMAID_CLI_CHROME_BIN` or
`PUPPETEER_EXECUTABLE_PATH` is not set.

kumeyuri CLI rendering does not need Chromium for text, SVG, GIF, APNG, or WebP
exports. Browser dependencies remain useful for WASM/web-component tests.

## Comparison harness

Keep mermaid-cli in benchmark jobs when you need Mermaid's browser renderer as a
ground-truth SVG baseline:

```sh
npm run bench:compare:mermaid-cli
npm run bench:compare:fidelity
```

The adapter writes SVG output and `.error.txt` failures under:

```text
benches/compare/results/mermaid-cli
```

## Known migration gaps

- Mermaid-native SVG and kumeyuri SVG are not byte- or shape-equivalent.
- PDF output is not a first-party kumeyuri CLI target yet.
- Mermaid config files and `themeCSS` do not map directly to kumeyuri themes.
- Use `COVERAGE.md` before migrating diagrams outside the supported root set.
