import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
const mainSource = fs.readFileSync(path.join(root, "main.js"), "utf8");
const playerSource = fs.readFileSync(path.join(root, "player.js"), "utf8");
const { parseFlags, renderCastTemplate } = await import(pathToFileURL(path.join(root, "main.js")).href);
const { frameText, validateCast } = await import(pathToFileURL(path.join(root, "player.js")).href);

assert.equal(pkg.logseq.id, "kumeyuri");
assert.match(mainSource, /onMacroRendererSlotted/);
assert.match(mainSource, /provideUI/);
assert.match(mainSource, /registerCommandPalette/);
assert.match(playerSource, /MutationObserver/);
assert.deepEqual(parseFlags(["autoplay", "loop"]), { autoplay: true, controls: true, loop: true });
assert.deepEqual(parseFlags(["no-controls"]), { autoplay: false, controls: false, loop: false });
assert.equal(
  renderCastTemplate("./casts/a&b.kumecast", { autoplay: true, controls: false, loop: true }),
  '<div class="kumeyuri-logseq-cast" data-kumeyuri-cast="./casts/a&amp;b.kumecast" data-autoplay="true" data-controls="false" data-loop="true">./casts/a&amp;b.kumecast</div>',
);

const cast = {
  version: 1,
  timeline: {
    frames: [{ width: 2, height: 1, durationMs: 10, cells: [{ glyph: "A" }, { glyph: "B" }] }],
  },
};
assert.equal(validateCast(cast), cast);
assert.equal(frameText(cast.timeline.frames[0]), "AB");

console.log("ok");
