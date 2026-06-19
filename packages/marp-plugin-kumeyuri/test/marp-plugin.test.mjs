import assert from "node:assert/strict";
import marpEngine, { marpKumeyuriPlugin, normalizeOptions, renderCastHtml } from "../index.js";

assert.equal(normalizeOptions().className, "kumeyuri-marp-cast");
assert.equal(normalizeOptions({ controls: false }).controls, false);
assert.throws(() => normalizeOptions(null), /options must be an object/);
assert.throws(() => normalizeOptions({ className: "" }), /className must be a non-empty string/);
assert.throws(() => normalizeOptions({ scriptUrl: "" }), /scriptUrl must be a non-empty string/);

assert.equal(
  renderCastHtml("./casts/a&b.kumecast", { autoplay: true, scriptUrl: "./player.js" }),
  '<div class="kumeyuri-marp-cast" data-kumeyuri-cast="./casts/a&amp;b.kumecast" data-autoplay data-controls></div>\n<script type="module" src="./player.js"></script>',
);

const state = {
  tokens: [
    { type: "paragraph_open", content: "" },
    { type: "fence", info: "kumecast", content: "./casts/demo.kumecast\n" },
    { type: "fence", info: "kumecast ./casts/inline.kumecast", content: "" },
    { type: "fence", info: "js", content: "console.log(1)" },
  ],
};
const md = markdownItMock(state);
marpKumeyuriPlugin(md, { controls: false });
md.run();

assert.equal(state.tokens[1].type, "html_block");
assert.match(state.tokens[1].content, /data-kumeyuri-cast="\.\/casts\/demo\.kumecast"/);
assert.doesNotMatch(state.tokens[1].content, /data-controls/);
assert.match(state.tokens[2].content, /data-kumeyuri-cast="\.\/casts\/inline\.kumecast"/);
assert.equal(state.tokens[3].type, "fence");

const calls = [];
const result = marpEngine({
  marp: {
    use(plugin, options) {
      calls.push({ plugin, options });
      return "engine";
    },
  },
}, { autoplay: true });

assert.equal(result, "engine");
assert.equal(calls[0].plugin, marpKumeyuriPlugin);
assert.deepEqual(calls[0].options, { autoplay: true });

function markdownItMock(state) {
  let rule = null;
  return {
    core: {
      ruler: {
        after(afterName, ruleName, fn) {
          assert.equal(afterName, "block");
          assert.equal(ruleName, "kumeyuri_cast_fences");
          rule = fn;
        },
      },
    },
    run() {
      rule(state);
    },
  };
}

console.log("ok");
