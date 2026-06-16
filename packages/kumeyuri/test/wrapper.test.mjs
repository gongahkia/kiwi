import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import { createKumeyuri, defineKumeyuriElement, initKumeyuri, render } from "../dist/index.js";

const calls = [];
const wasm = {
  initialized: false,
  async default() {
    this.initialized = true;
  },
  render(source, options) {
    calls.push({ source, options });
    return {
      svg: `<svg data-theme="${options.theme ?? "default"}"></svg>`,
      frames: [{ text: "A --> B", durationMs: 550 }],
    };
  },
};

const client = createKumeyuri(wasm);
const output = client.render("graph TD\\nA --> B", { theme: "github" });
assert.equal(output.svg, '<svg data-theme="github"></svg>');
assert.deepEqual(output.frames, [{ text: "A --> B", durationMs: 550 }]);

await initKumeyuri(async () => wasm);
assert.equal(wasm.initialized, true);
assert.equal(render("graph TD\\nA --> B").frames[0].durationMs, 550);

assert.throws(
  () => createKumeyuri({ render: () => ({ svg: 1, frames: [] }) }).render("x"),
  /svg must be a string/,
);

const dom = new JSDOM("<!doctype html><body></body>", { url: "https://example.test/" });
globalThis.customElements = dom.window.customElements;
globalThis.document = dom.window.document;
globalThis.HTMLElement = dom.window.HTMLElement;
globalThis.fetch = async (url) => ({
  ok: true,
  status: 200,
  text: async () => `graph TD\\n${url} --> B`,
});

defineKumeyuriElement();
const inlineElement = document.createElement("kumeyuri-diagram");
inlineElement.setAttribute("inline", "graph TD\\nA --> B");
inlineElement.setAttribute("animate", "trace");
inlineElement.setAttribute("theme", "github");
inlineElement.setAttribute("speed", "1.5");
inlineElement.setAttribute("autoplay", "");
inlineElement.setAttribute("controls", "");
document.body.append(inlineElement);
await tick();

assert.equal(inlineElement.dataset.autoplay, "true");
assert.equal(inlineElement.dataset.controls, "true");
assert.equal(inlineElement.querySelector("svg")?.getAttribute("data-theme"), "github");
assert.match(calls.at(-1).source, /^%%\{ animate: 'trace' \}%%\n/);
assert.equal(calls.at(-1).options.speed, 1.5);

const srcElement = document.createElement("kumeyuri-diagram");
srcElement.setAttribute("src", "remote.mmd");
document.body.append(srcElement);
await tick();

assert.match(calls.at(-1).source, /remote\.mmd --> B/);

function tick() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}
