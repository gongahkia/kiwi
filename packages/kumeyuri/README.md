# kumeyuri

Typed browser wrapper for the kumeyuri WASM renderer.

```ts
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { initKumeyuri, render } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });
const { svg, frames } = render("graph TD\nA --> B", {
  theme: "github",
  charset: "unicode",
});
```
