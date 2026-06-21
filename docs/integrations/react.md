# React

`packages/kumeyuri` exposes `kumeyuri/react`, a typed adapter around the browser
custom element. Use it in client-rendered React code after making the
wasm-bindgen module available to the app.

```tsx
import initWasm, * as wasm from "./pkg/kumeyuri_render_wasm.js";
import { KumeyuriDiagram, KumeyuriProvider } from "kumeyuri/react";

const kumeyuriModule = { ...wasm, default: initWasm };

export function Diagram() {
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

`KumeyuriDiagram` maps `darkTheme` to `dark-theme` and omits false boolean
attributes. Use `src` for static Mermaid files, `inline` for small inline source,
or children when the diagram source should live inside the element body.
