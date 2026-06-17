import assert from "node:assert/strict";
import kumeyuri, { browserImport, normalizeOptions } from "../index.js";

const calls = [];
const integration = kumeyuri({
  scriptUrl: "/kumeyuri/player.js",
  stage: "page",
});

assert.equal(integration.name, "@kumeyuri/astro");
integration.hooks["astro:config:setup"]({
  injectScript(stage, content) {
    calls.push({ stage, content });
  },
});

assert.deepEqual(calls, [{ stage: "page", content: 'import("/kumeyuri/player.js");' }]);
assert.equal(browserImport("https://cdn.example/player.js"), 'import("https://cdn.example/player.js");');
assert.equal(normalizeOptions().scriptUrl, "https://cdn.kumeyuri.dev/player.js");
assert.equal(normalizeOptions({ inject: false }).inject, false);
assert.throws(() => normalizeOptions(null), /options must be an object/);
assert.throws(() => normalizeOptions({ scriptUrl: "" }), /scriptUrl must be a non-empty string/);
assert.throws(() => normalizeOptions({ stage: "server" }), /stage must be one of/);

console.log("ok");
