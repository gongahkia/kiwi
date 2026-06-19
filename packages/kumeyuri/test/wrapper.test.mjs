import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import { createKumeyuri, defineKumeyuriElement, initKumeyuri, render, renderCast } from "../dist/index.js";

const calls = [];
const wasm = {
  initialized: false,
  async default() {
    this.initialized = true;
  },
  render(source, options) {
    calls.push({ kind: "mermaid", source, options });
    return {
      svg: `<svg data-kind="mermaid" data-theme="${options.theme ?? "default"}" data-dark-theme="${options.darkTheme ?? ""}"></svg>`,
      frames: [
        { text: "A", durationMs: 550 },
        { text: "B", durationMs: 650 },
      ],
    };
  },
  renderCast(source, options) {
    calls.push({ kind: "cast", source, options });
    return {
      svg: `<svg data-kind="cast" data-theme="${options.theme ?? "default"}"></svg>`,
      frames: [
        { text: "C", durationMs: 750 },
        { text: "D", durationMs: 850 },
      ],
    };
  },
};

const client = createKumeyuri(wasm);
const output = client.render("graph TD\\nA --> B", { theme: "github", darkTheme: "dracula" });
assert.equal(output.svg, '<svg data-kind="mermaid" data-theme="github" data-dark-theme="dracula"></svg>');
assert.deepEqual(output.frames, [
  { text: "A", durationMs: 550 },
  { text: "B", durationMs: 650 },
]);
assert.equal(client.renderCast('{"version":1}', { theme: "github" }).frames[0].text, "C");

await initKumeyuri(async () => wasm);
assert.equal(wasm.initialized, true);
assert.equal(render("graph TD\\nA --> B").frames[0].durationMs, 550);
assert.equal(renderCast('{"version":1}').frames[0].durationMs, 750);

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
  text: async () => url.endsWith(".kumecast") ? `{"version":1,"source":"${url}"}` : `graph TD\\n${url} --> B`,
});

defineKumeyuriElement();
const inlineElement = document.createElement("kumeyuri-diagram");
inlineElement.setAttribute("inline", "graph TD\\nA --> B");
inlineElement.setAttribute("animate", "trace");
inlineElement.setAttribute("theme", "github");
inlineElement.setAttribute("dark-theme", "dracula");
inlineElement.setAttribute("speed", "1.5");
inlineElement.setAttribute("autoplay", "");
inlineElement.setAttribute("controls", "");
document.body.append(inlineElement);
await tick();

assert.equal(inlineElement.dataset.autoplay, "true");
assert.equal(inlineElement.dataset.controls, "true");
assert.equal(inlineElement.querySelector("svg")?.getAttribute("data-theme"), "github");
assert.equal(inlineElement.querySelector("svg")?.getAttribute("data-dark-theme"), "dracula");
assert.match(calls.at(-1).source, /^%%\{ animate: 'trace' \}%%\n/);
assert.equal(calls.at(-1).options.darkTheme, "dracula");
assert.equal(calls.at(-1).options.speed, 1.5);
assert.equal(inlineElement.querySelector("[data-kumeyuri-controls]") !== null, true);
assert.equal(inlineElement.querySelector("input[type='range']")?.getAttribute("max"), "1");
assert.equal(inlineElement.querySelector("button[data-action='play']")?.textContent, "pause");
inlineElement.querySelector("button[data-action='play']")?.click();
assert.equal(inlineElement.querySelector("button[data-action='play']")?.textContent, "play");

const srcElement = document.createElement("kumeyuri-diagram");
srcElement.setAttribute("src", "remote.mmd");
document.body.append(srcElement);
await tick();

assert.match(calls.at(-1).source, /remote\.mmd --> B/);
assert.equal(calls.at(-1).kind, "mermaid");

const castElement = document.createElement("kumeyuri-diagram");
castElement.setAttribute("src", "remote.kumecast");
castElement.setAttribute("animate", "trace");
document.body.append(castElement);
await tick();

assert.equal(calls.at(-1).kind, "cast");
assert.match(calls.at(-1).source, /remote\.kumecast/);
assert.equal(castElement.querySelector("svg")?.getAttribute("data-kind"), "cast");

function tick() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}
