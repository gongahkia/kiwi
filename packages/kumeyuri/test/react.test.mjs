import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { KumeyuriDiagram, KumeyuriProvider } from "../dist/react.js";

const html = renderToString(
  createElement(KumeyuriDiagram, {
    inline: "graph TD\nA --> B",
    animate: "trace",
    theme: "github",
    darkTheme: "tokyo-night",
    speed: 1.25,
    autoplay: true,
    controls: true,
    className: "diagram",
  }),
);
assert.match(html, /^<kumeyuri-diagram /);
assert.match(html, /inline="graph TD\nA --&gt; B"/);
assert.match(html, /animate="trace"/);
assert.match(html, /theme="github"/);
assert.match(html, /dark-theme="tokyo-night"/);
assert.match(html, /speed="1.25"/);
assert.match(html, /autoplay=""/);
assert.match(html, /controls=""/);
assert.match(html, /class="diagram"/);

const dom = new JSDOM("<!doctype html><body><div id=\"root\"></div></body>", { url: "https://example.test/" });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.customElements = dom.window.customElements;
globalThis.HTMLElement = dom.window.HTMLElement;

const { createRoot } = await import("react-dom/client");
const calls = [];
const wasm = {
  async default(input) {
    calls.push({ kind: "init", input });
  },
  render(source, options) {
    calls.push({ kind: "render", source, options });
    return {
      svg: `<svg data-theme="${options.theme ?? "default"}"></svg>`,
      frames: [],
    };
  },
};

let ready = false;
let failure;
const root = createRoot(document.getElementById("root"));
root.render(
  createElement(
    KumeyuriProvider,
    {
      moduleOrLoader: async () => wasm,
      initInput: "seed",
      onReady: () => {
        ready = true;
      },
      onError: (error) => {
        failure = error;
      },
    },
    createElement(KumeyuriDiagram, {
      inline: "graph TD\nA --> B",
      theme: "github",
      autoplay: false,
      controls: true,
    }),
  ),
);

await eventually(() => ready);
await tick();

assert.equal(failure, undefined);
assert.equal(customElements.get("kumeyuri-diagram") !== undefined, true);
assert.deepEqual(calls[0], { kind: "init", input: "seed" });
assert.equal(calls.at(-1).kind, "render");
assert.equal(calls.at(-1).options.theme, "github");
const element = document.querySelector("kumeyuri-diagram");
assert.equal(element.getAttribute("inline"), "graph TD\nA --> B");
assert.equal(element.hasAttribute("autoplay"), false);
assert.equal(element.getAttribute("controls"), "");
assert.equal(element.querySelector("svg")?.getAttribute("data-theme"), "github");

function tick() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function eventually(predicate) {
  for (let i = 0; i < 20; i += 1) {
    if (predicate()) {
      return;
    }
    await tick();
  }
  assert.equal(predicate(), true);
}
