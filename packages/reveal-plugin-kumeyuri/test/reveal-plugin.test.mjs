import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import plugin, { frameText, normalizeOptions, validateCast } from "../index.js";

const cast = {
  version: 1,
  source: { diagramType: "flowchart" },
  timeline: {
    repeat: false,
    frames: [
      frame(2, 2, ["A", "-", "|", "B"], 25),
      frame(2, 2, ["C", "-", "|", "D"], 25),
    ],
  },
};

assert.equal(normalizeOptions().selector, "[data-kumeyuri-cast]");
assert.equal(normalizeOptions({ controls: false }).controls, false);
assert.throws(() => normalizeOptions(null), /options must be an object/);
assert.throws(() => normalizeOptions({ selector: "" }), /selector must be a non-empty string/);
assert.throws(() => normalizeOptions({ autoplay: "yes" }), /autoplay must be a boolean/);
assert.equal(validateCast(cast), cast);
assert.throws(() => validateCast({ version: 2 }), /unsupported cast version/);
assert.equal(frameText(cast.timeline.frames[0]), "A-\n|B");

const dom = new JSDOM(`
  <main class="reveal">
    <section>
      <div id="cast" data-kumeyuri-cast="/casts/demo.kumecast"></div>
    </section>
  </main>
`);
globalThis.document = dom.window.document;
globalThis.setTimeout = dom.window.setTimeout.bind(dom.window);
globalThis.clearTimeout = dom.window.clearTimeout.bind(dom.window);

const calls = [];
const instance = plugin({
  fetcher: async (url, init) => {
    calls.push({ url, accept: init.headers.Accept });
    return {
      ok: true,
      status: 200,
      async json() {
        return cast;
      },
    };
  },
});

assert.equal(instance.id, "kumeyuri");
await instance.init({
  getRevealElement() {
    return dom.window.document.querySelector(".reveal");
  },
});

assert.deepEqual(calls, [{ url: "/casts/demo.kumecast", accept: "application/json, */*;q=0.1" }]);
assert.equal(dom.window.document.querySelector(".kumeyuri-reveal-cast-frame").textContent, "A-\n|B");
assert.equal(dom.window.document.querySelector(".kumeyuri-reveal-cast-meta").textContent, "flowchart / 2 frames");
assert.equal(dom.window.document.querySelector(".kumeyuri-reveal-cast-controls button").textContent, "Play");

instance.destroy();
delete globalThis.document;

function frame(width, height, glyphs, durationMs) {
  return {
    width,
    height,
    durationMs,
    cells: glyphs.map((glyph) => ({ glyph })),
  };
}

console.log("ok");
