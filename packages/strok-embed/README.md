# @strok/embed

Embeddable strok ANSI/asciinema player for HTML and React. The package ships a Web Component, a small ANSI/asciinema parser, and a React wrapper.

This package replays exported `.ansi` and `.cast` output in the browser. It does not run the native C++ renderer or decode source media in-browser.

## Install From This Repo

```sh
npm install ./packages/strok-embed
```

`@strok/embed` is the package name in `package.json`; it is not published to npm yet.

## HTML

```html
<script type="module">
  import { defineStrokPlayer } from "@strok/embed";
  defineStrokPlayer();
</script>

<strok-player src="/demo.cast" controls autoplay loop></strok-player>
```

Inline ANSI is supported when no `src` is set:

```html
<script type="module" src="/node_modules/@strok/embed/dist/strok-embed.js"></script>

<strok-player format="ansi" cols="80" rows="24" controls>
hello &#x1b;[32mstrok&#x1b;[0m
</strok-player>
```

## React

```jsx
import { StrokPlayer } from "@strok/embed/react";

export function Demo() {
  return <StrokPlayer src="/demo.cast" controls autoPlay loop />;
}
```

## Export Then Embed

```sh
strok --input demo.mp4 --mode structure --width 100 --height 32 --export demo.cast
```

Serve `demo.cast` from the same origin as the page, or enable CORS on the asset host.

## Markdown

Static Markdown can embed exported media:

```md
![strok demo](demo.gif)

<video src="demo.mp4" controls></video>
```

GitHub Markdown does not execute JavaScript, so `<strok-player>` only works in JS-enabled Markdown systems such as MDX, Docusaurus, Astro, or documentation sites that allow custom scripts.

## API

```js
import {
  AnsiScreen,
  defineStrokPlayer,
  parseAnsi,
  parseCast,
  parseRecording,
  recordingToHtml,
  renderRecordingFrame,
} from "@strok/embed";
```

`<strok-player>` attributes:

| Attribute | Meaning |
|---|---|
| `src` | URL to `.cast` or `.ansi` text. |
| `format` | `auto`, `cast`, or `ansi`. |
| `cols` / `rows` | Terminal dimensions for raw ANSI input. Cast files use their header unless overridden. |
| `controls` | Shows play/pause and seek controls. |
| `autoplay` | Starts playback after load. |
| `loop` | Restarts at EOF. |
| `speed` | Playback multiplier. |

Events: `strok-load`, `strok-error`, `strok-timeupdate`, and `strok-ended`.

CSS custom properties: `--strok-font`, `--strok-bg`, `--strok-fg`, `--strok-border`, `--strok-padding`, `--strok-control-fg`, and `--strok-button-bg`.

## Limits

- ANSI parsing intentionally covers common terminal recording output: SGR color, cursor motion, clears, tabs, CR/LF, and OSC skipping.
- GitHub Markdown cannot run the component.
- For universal Markdown embeds, export GIF/PNG/MP4 from the native CLI.
