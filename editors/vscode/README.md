# Kumeyuri VSCode

VSCode extension for previewing `.mmd` and `.mermaid` files with the kumeyuri WASM player.

## Features

- `Kumeyuri: Preview Mermaid` opens a webview preview beside the active editor.
- The webview uses the same `kumeyuri` browser wrapper and WASM renderer as the npm package.
- Saving the previewed Mermaid file refreshes the webview when `kumeyuri.preview.autoRenderOnSave` is enabled.

## Development

Run the helper tests:

```sh
npm --prefix editors/vscode test
```

The extension vendors generated assets in `media/` so it can be packaged without reading files outside the extension directory.
