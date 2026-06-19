import assert from "node:assert/strict";
import Kumeyuri, { normalizeOptions, remarkKumeyuri, renderCastHtml } from "../index.js";

assert.equal(normalizeOptions().className, "kumeyuri-quartz-cast");
assert.equal(normalizeOptions({ controls: false }).controls, false);
assert.throws(() => normalizeOptions(null), /options must be an object/);
assert.throws(() => normalizeOptions({ autoplay: "yes" }), /autoplay must be a boolean/);
assert.equal(
  renderCastHtml('/casts/a"b.kumecast', { loop: true }),
  '<div class="kumeyuri-quartz-cast" data-kumeyuri-cast="/casts/a&quot;b.kumecast" data-controls="true" data-loop="true"></div>',
);

const plugin = Kumeyuri({ scriptUrl: "/kumeyuri/player.js", cssUrl: "/kumeyuri/player.css" });
assert.equal(plugin.name, "Kumeyuri");
assert.equal(plugin.markdownPlugins().length, 1);
assert.deepEqual(plugin.externalResources(), {
  js: [{ src: "/kumeyuri/player.js", loadTime: "afterDOMReady", contentType: "external" }],
  css: ["/kumeyuri/player.css"],
});

const tree = {
  type: "root",
  children: [
    { type: "code", lang: "kumecast", value: "/casts/demo.kumecast\n" },
    { type: "code", lang: "js", value: "console.log(1)" },
  ],
};
remarkKumeyuri({ autoplay: true })(tree);
assert.equal(tree.children[0].type, "html");
assert.match(tree.children[0].value, /data-kumeyuri-cast="\/casts\/demo\.kumecast"/);
assert.match(tree.children[0].value, /data-autoplay="true"/);
assert.equal(tree.children[1].type, "code");

console.log("ok");
