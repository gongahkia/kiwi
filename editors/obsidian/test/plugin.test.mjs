import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
const styles = fs.readFileSync(path.join(root, "styles.css"), "utf8");
const moduleUrl = pathToFileURL(path.join(root, "main.js")).href;
const pluginModule = await import(moduleUrl);
const plugin = pluginModule.default;
const { DEFAULT_SETTINGS } = plugin;

assert.equal(manifest.id, "kumeyuri");
assert.equal(manifest.isDesktopOnly, true);
assert.equal(typeof plugin, "function");
assert.equal(DEFAULT_SETTINGS.cliPath, "kumeyuri");
assert.match(styles, /kumeyuri-obsidian-frame/);

const source = fs.readFileSync(path.join(root, "main.js"), "utf8");
assert.match(source, /registerMarkdownCodeBlockProcessor\("mermaid"/);
assert.match(source, /registerMarkdownCodeBlockProcessor\("kumeyuri"/);
assert.match(source, /execFileAsync/);
assert.match(source, /"render", input, "--format", "text"/);

console.log("ok");
