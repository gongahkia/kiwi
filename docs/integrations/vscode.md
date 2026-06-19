# VSCode

`editors/vscode` previews `.mmd` and `.mermaid` files with the kumeyuri WASM
player.

Command:

```text
Kumeyuri: Preview Mermaid
```

The preview refreshes on save when `kumeyuri.preview.autoRenderOnSave` is
enabled. Run extension tests with:

```sh
npm --prefix editors/vscode test
```
