import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
const component = fs.readFileSync(path.join(root, "components/KumeyuriDiagram.vue"), "utf8");
const readme = fs.readFileSync(path.join(root, "README.md"), "utf8");

assert.equal(pkg.name, "slidev-addon-kumeyuri");
assert.deepEqual(pkg.files, ["components", "README.md"]);
assert.match(component, /defineProps\(\{/);
assert.match(component, /src: \{ type: String, required: true \}/);
assert.match(component, /function validateCast/);
assert.match(component, /function frameText/);
assert.match(component, /aria-live="polite"/);
assert.match(readme, /<KumeyuriDiagram src="\/casts\/oauth-login\.kumecast"/);

console.log("ok");
