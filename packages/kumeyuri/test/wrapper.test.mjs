import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import { createKumeyuri, defineKumeyuriElement, initKumeyuri, render, renderCast } from "../dist/index.js";

const bundledWasm = await import("../wasm/kumeyuri_render_wasm.js");
assert.equal(typeof bundledWasm.default, "function");
assert.equal(typeof bundledWasm.render, "function");
assert.equal(typeof bundledWasm.renderCast, "function");

const calls = [];
const wasm = {
  initialized: false,
  async default() {
    this.initialized = true;
  },
  render(source, options) {
    calls.push({ kind: "mermaid", source, options });
    if (source.includes("BAD")) {
      throw new Error("bad diagram");
    }
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
  headers: {
    get(name) {
      return name === "content-length" && url === "large.mmd" ? "12" : null;
    },
  },
  text: async () => url.endsWith(".kumecast") ? `{"version":1,"source":"${url}"}` : `graph TD\\n${url} --> B`,
});

defineKumeyuriElement();
const inlineElement = document.createElement("kumeyuri-diagram");
inlineElement.setAttribute("inline", "graph TD\\nA --> B");
inlineElement.setAttribute("animate", "trace");
inlineElement.setAttribute("theme", "github");
inlineElement.setAttribute("dark-theme", "dracula");
inlineElement.setAttribute("charset", "unicode");
inlineElement.setAttribute("width", "80");
inlineElement.setAttribute("padding", "12");
inlineElement.setAttribute("font", "ui-monospace");
inlineElement.setAttribute("speed", "1.5");
inlineElement.setAttribute("loop", "");
inlineElement.setAttribute("svg-animation", "css-keyframes");
inlineElement.setAttribute("autoplay", "");
inlineElement.setAttribute("controls", "");
document.body.append(inlineElement);
await tick();

assert.equal(inlineElement.dataset.autoplay, "true");
assert.equal(inlineElement.dataset.controls, "true");
assert.equal(inlineElement.dataset.loop, "true");
assert.equal(inlineElement.dataset.reducedMotion, "false");
assert.equal(inlineElement.querySelector("svg")?.getAttribute("data-theme"), "github");
assert.equal(inlineElement.querySelector("svg")?.getAttribute("data-dark-theme"), "dracula");
assert.match(calls.at(-1).source, /^%%\{ animate: 'trace' \}%%\n/);
assert.equal(calls.at(-1).options.darkTheme, "dracula");
assert.equal(calls.at(-1).options.charset, "unicode");
assert.equal(calls.at(-1).options.width, 80);
assert.equal(calls.at(-1).options.padding, 12);
assert.equal(calls.at(-1).options.font, "ui-monospace");
assert.equal(calls.at(-1).options.speed, 1.5);
assert.equal(calls.at(-1).options.repeat, true);
assert.equal(calls.at(-1).options.svgAnimation, "css-keyframes");
assert.equal(inlineElement.querySelector("[data-kumeyuri-controls]") !== null, true);
assert.equal(inlineElement.querySelector("input[type='range']")?.getAttribute("max"), "1");
assert.equal(inlineElement.querySelector("button[data-action='play']")?.textContent, "pause");
inlineElement.querySelector("button[data-action='play']")?.click();
assert.equal(inlineElement.querySelector("button[data-action='play']")?.textContent, "play");
inlineElement.play();
assert.equal(inlineElement.querySelector("button[data-action='play']")?.textContent, "pause");
inlineElement.pause();
assert.equal(inlineElement.querySelector("button[data-action='play']")?.textContent, "play");
inlineElement.seek(1);
assert.equal(inlineElement.querySelector("input[type='range']")?.value, "1");
assert.match(inlineElement.exportSvg(), /data-kind="mermaid"/);

const sourceElement = document.createElement("kumeyuri-diagram");
sourceElement.setAttribute("source", "graph TD\nS --> T");
sourceElement.setAttribute("reduced-motion", "reduce");
sourceElement.setAttribute("autoplay", "");
sourceElement.setAttribute("controls", "");
document.body.append(sourceElement);
await tick();

assert.equal(calls.at(-1).source, "graph TD\nS --> T");
assert.equal(sourceElement.dataset.reducedMotion, "true");
assert.equal(sourceElement.querySelector("button[data-action='play']")?.textContent, "play");

const scriptSourceElement = document.createElement("kumeyuri-diagram");
scriptSourceElement.innerHTML =
  '<svg id="ssr-fallback"></svg><script type="text/plain" data-kumeyuri-source>graph TD\nQ --> R</script>';
document.body.append(scriptSourceElement);
await tick();

assert.equal(calls.at(-1).source, "graph TD\nQ --> R");
scriptSourceElement.setAttribute("theme", "nord");
await tick();
assert.equal(calls.at(-1).source, "graph TD\nQ --> R");
assert.equal(calls.at(-1).options.theme, "nord");

const cspElement = document.createElement("kumeyuri-diagram");
cspElement.setAttribute("source", "graph TD\nC --> S");
cspElement.setAttribute("controls", "");
cspElement.setAttribute("csp", "");
document.body.append(cspElement);
await tick();

assert.equal(cspElement.querySelector("[data-kumeyuri-csp]")?.getAttribute("style"), null);
assert.equal(cspElement.querySelector("button[data-action='play']")?.getAttribute("style"), null);
assert.equal(cspElement.querySelector("input[type='range']")?.getAttribute("style"), null);

const badElement = document.createElement("kumeyuri-diagram");
badElement.setAttribute("source", "BAD");
badElement.innerHTML = '<svg id="fallback-svg"></svg><noscript><img src="/diagram.svg" alt="fallback"></noscript>';
document.body.append(badElement);
await tick();

assert.equal(badElement.dataset.error, "bad diagram");
assert.equal(badElement.querySelector("#fallback-svg") !== null, true);
assert.equal(badElement.innerHTML.includes("diagram.svg"), true);

const limitedInlineElement = document.createElement("kumeyuri-diagram");
limitedInlineElement.setAttribute("source", "graph TD\nTooLarge --> B");
limitedInlineElement.setAttribute("max-source-bytes", "8");
document.body.append(limitedInlineElement);
await tick();

assert.match(limitedInlineElement.dataset.error ?? "", /max-source-bytes/);
assert.equal(limitedInlineElement.querySelector("[data-kumeyuri-error]")?.getAttribute("role"), "alert");

const limitedSrcElement = document.createElement("kumeyuri-diagram");
limitedSrcElement.setAttribute("src", "large.mmd");
limitedSrcElement.setAttribute("max-source-bytes", "8");
document.body.append(limitedSrcElement);
await tick();

assert.match(limitedSrcElement.dataset.error ?? "", /max-source-bytes/);

const srcElement = document.createElement("kumeyuri-diagram");
srcElement.setAttribute("src", "remote.mmd");
srcElement.setAttribute("fetch-timeout-ms", "2500");
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
