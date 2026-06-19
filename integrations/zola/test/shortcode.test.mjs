import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = path.resolve("integrations/zola");
const shortcode = fs.readFileSync(path.join(root, "templates/shortcodes/kumeyuri.html"), "utf8");
const css = fs.readFileSync(path.join(root, "static/kumeyuri.css"), "utf8");
const player = fs.readFileSync(path.join(root, "static/kumeyuri-player.js"), "utf8");
const { frameText, validateCast } = await import(pathToFileURL(path.join(root, "static/kumeyuri-player.js")).href);

assert.match(shortcode, /data-kumeyuri-cast="{{ src }}"/);
assert.match(shortcode, /data-controls=/);
assert.match(shortcode, /data-autoplay="true"/);
assert.match(shortcode, /data-loop="true"/);
assert.match(css, /kumeyuri-zola-frame/);
assert.match(player, /querySelectorAll\("\[data-kumeyuri-cast\]/);
assert.match(player, /MutationObserver/);

const cast = {
  version: 1,
  timeline: {
    frames: [{ width: 2, height: 1, durationMs: 10, cells: [{ glyph: "A" }, { glyph: "B" }] }],
  },
};
assert.equal(validateCast(cast), cast);
assert.equal(frameText(cast.timeline.frames[0]), "AB");

console.log("ok");
