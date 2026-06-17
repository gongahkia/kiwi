import assert from "node:assert/strict";
import plugin, { normalizeOptions, validateOptions } from "../index.js";

const instance = plugin(context(), {
  scriptUrl: "/kumeyuri/player.js",
  preload: true,
  integrity: "sha384-test",
  crossorigin: "anonymous",
});

assert.equal(instance.name, "@docusaurus/plugin-kumeyuri");

const tags = instance.injectHtmlTags();
assert.deepEqual(tags.headTags, [
  {
    tagName: "link",
    attributes: {
      rel: "modulepreload",
      href: "/kumeyuri/player.js",
      integrity: "sha384-test",
      crossorigin: "anonymous",
    },
  },
]);
assert.deepEqual(tags.postBodyTags, [
  {
    tagName: "script",
    attributes: {
      type: "module",
      src: "/kumeyuri/player.js",
      integrity: "sha384-test",
      crossorigin: "anonymous",
    },
  },
]);

assert.deepEqual(plugin(context(), { inject: false }).injectHtmlTags(), {});
assert.equal(normalizeOptions().scriptUrl, "https://cdn.kumeyuri.dev/player.js");
assert.equal(validateOptions({ options: { scriptUrl: "/x.js" } }).scriptUrl, "/x.js");
assert.throws(() => normalizeOptions(null), /options must be an object/);
assert.throws(() => normalizeOptions({ scriptUrl: "" }), /scriptUrl must be a non-empty string/);
assert.throws(() => normalizeOptions({ preload: "yes" }), /preload must be a boolean/);

function context() {
  return {
    siteDir: "/site",
    generatedFilesDir: "/site/.docusaurus",
    siteConfig: {},
    outDir: "/site/build",
    baseUrl: "/",
  };
}

console.log("ok");
