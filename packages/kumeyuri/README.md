# kumeyuri

Typed browser wrapper for the kumeyuri WASM renderer.

```ts
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { initKumeyuri, render } from "kumeyuri";

await initKumeyuri({ ...wasm, default: initWasm });
const { svg, frames } = render("graph TD\nA --> B", {
  theme: "github",
  darkTheme: "tokyo-night",
  charset: "unicode",
});
```

## React

`kumeyuri/react` wraps the same custom element for React apps and maps camelCase
props to the element's dashed attributes.

```tsx
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { KumeyuriDiagram, KumeyuriProvider } from "kumeyuri/react";

const kumeyuriModule = { ...wasm, default: initWasm };

export function App() {
  return (
    <KumeyuriProvider moduleOrLoader={kumeyuriModule}>
      <KumeyuriDiagram
        src="/diagrams/flow.mmd"
        animate="trace"
        theme="github"
        darkTheme="tokyo-night"
        speed={1.25}
        autoplay
        controls
      />
    </KumeyuriProvider>
  );
}
```
