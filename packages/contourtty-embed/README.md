# @contourtty/embed

Embeddable contourtty ANSI/asciinema player for HTML and React. The package ships a Web Component, a small ANSI/asciinema parser, and a React wrapper.

This package replays exported `.ansi` and `.cast` output in the browser. It does not run the native C++ renderer or decode source media in-browser.

## Install From This Repo

```sh
npm install ./packages/contourtty-embed
```

`@contourtty/embed` is the package name in `package.json`; it is not published to npm yet.

## HTML

```html
<script type="module">
  import { defineContourttyPlayer } from "@contourtty/embed";
  defineContourttyPlayer();
</script>

<contourtty-player src="/demo.cast" controls autoplay loop></contourtty-player>
```

Inline ANSI is supported when no `src` is set:

```html
<script type="module" src="/node_modules/@contourtty/embed/dist/contourtty-embed.js"></script>

<contourtty-player format="ansi" cols="80" rows="24" controls>
hello &#x1b;[32mcontourtty&#x1b;[0m
</contourtty-player>
```

## React

```jsx
import { ContourttyPlayer } from "@contourtty/embed/react";

export function Demo() {
  return <ContourttyPlayer src="/demo.cast" controls autoPlay loop />;
}
```

## Export Then Embed

```sh
contourtty --input demo.mp4 --mode structure --width 100 --height 32 --export demo.cast
```

Serve `demo.cast` from the same origin as the page, or enable CORS on the asset host.

## Markdown

Static Markdown can embed exported media:

```md
![contourtty demo](demo.gif)

<video src="demo.mp4" controls></video>
```

GitHub Markdown does not execute JavaScript, so `<contourtty-player>` only works in JS-enabled Markdown systems such as MDX, Docusaurus, Astro, or documentation sites that allow custom scripts.

## API

```js
import {
  AnsiScreen,
  defineContourttyPlayer,
  parseAnsi,
  parseCast,
  parseRecording,
  recordingToHtml,
  renderRecordingFrame,
} from "@contourtty/embed";
```

`<contourtty-player>` attributes:

| Attribute | Meaning |
|---|---|
| `src` | URL to `.cast` or `.ansi` text. |
| `format` | `auto`, `cast`, or `ansi`. |
| `cols` / `rows` | Terminal dimensions for raw ANSI input. Cast files use their header unless overridden. |
| `controls` | Shows play/pause and seek controls. |
| `autoplay` | Starts playback after load. |
| `loop` | Restarts at EOF. |
| `speed` | Playback multiplier. |

Events: `contourtty-load`, `contourtty-error`, `contourtty-timeupdate`, and `contourtty-ended`.

CSS custom properties: `--contourtty-font`, `--contourtty-bg`, `--contourtty-fg`, `--contourtty-border`, `--contourtty-padding`, `--contourtty-control-fg`, and `--contourtty-button-bg`.

## Limits

- ANSI parsing intentionally covers common terminal recording output: SGR color, cursor motion, clears, tabs, CR/LF, and OSC skipping.
- GitHub Markdown cannot run the component.
- For universal Markdown embeds, export GIF/PNG/MP4 from the native CLI.
