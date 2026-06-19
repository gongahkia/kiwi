# Web Component

Use `packages/kumeyuri` when a site needs live browser rendering instead of
pre-rendered assets.

```ts
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { defineKumeyuriElement, initKumeyuri } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });
defineKumeyuriElement();
```

```html
<kumeyuri-diagram src="/diagrams/flow.mmd" animate="trace" theme="github" controls></kumeyuri-diagram>
```

Use static SVG/GIF/APNG/WebP assets when the page does not need client-side
source loading or controls.
