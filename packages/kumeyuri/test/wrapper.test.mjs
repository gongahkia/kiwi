import assert from "node:assert/strict";
import { createKumeyuri, initKumeyuri, render } from "../dist/index.js";

const wasm = {
  initialized: false,
  async default() {
    this.initialized = true;
  },
  render(source, options) {
    return {
      svg: `<svg data-source="${source}" data-theme="${options.theme ?? "default"}"></svg>`,
      frames: [{ text: "A --> B", durationMs: 550 }],
    };
  },
};

const client = createKumeyuri(wasm);
const output = client.render("graph TD\\nA --> B", { theme: "github" });
assert.equal(output.svg, '<svg data-source="graph TD\\nA --> B" data-theme="github"></svg>');
assert.deepEqual(output.frames, [{ text: "A --> B", durationMs: 550 }]);

await initKumeyuri(async () => wasm);
assert.equal(wasm.initialized, true);
assert.equal(render("graph TD\\nA --> B").frames[0].durationMs, 550);

assert.throws(
  () => createKumeyuri({ render: () => ({ svg: 1, frames: [] }) }).render("x"),
  /svg must be a string/,
);
