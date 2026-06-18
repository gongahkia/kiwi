#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const pluginsDir = path.join(root, "plugins");
const allPluginNames = fs.existsSync(pluginsDir)
  ? fs.readdirSync(pluginsDir).filter((name) => !name.startsWith(".")).sort()
  : [];
const requestedPluginNames = process.argv.slice(2);
const pluginNames = requestedPluginNames.length > 0 ? requestedPluginNames : allPluginNames;

if (pluginNames.length === 0) {
  throw new Error("no reference plugins found");
}

for (const pluginName of pluginNames) {
  if (!allPluginNames.includes(pluginName)) {
    throw new Error(`${pluginName}: reference plugin not found`);
  }
  const pluginDir = path.join(pluginsDir, pluginName);
  const packageJson = readJson(path.join(pluginDir, "package.json"));
  const manifest = readJson(path.join(pluginDir, "kumeyuri.plugin.json"));

  assertEqual(packageJson.name, manifest.name, `${pluginName}: package/manifest name mismatch`);
  assertEqual(packageJson.version, manifest.version, `${pluginName}: package/manifest version mismatch`);
  assertIncludes(packageJson.keywords ?? [], "kumeyuri-plugin", `${pluginName}: missing npm keyword`);
  assertEqual(manifest.abi, "1.0", `${pluginName}: unexpected ABI`);
  assertEqual(path.isAbsolute(manifest.entry), false, `${pluginName}: entry must be relative`);
  assertEqual(path.extname(manifest.entry), ".wasm", `${pluginName}: entry must be .wasm`);
  assertEqual(Array.isArray(manifest.capabilities), true, `${pluginName}: capabilities must be an array`);
  assertKindExport(pluginName, manifest);
  assertEntryLooksLikeWasm(path.join(pluginDir, manifest.entry), pluginName);
}

console.log(`validated ${pluginNames.length} reference plugin package(s)`);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function assertKindExport(pluginName, manifest) {
  const required = {
    "render-backend": "renderBackend",
    "diagram-type": "diagramType",
    "theme-transform": "themeTransform"
  }[manifest.kind];
  if (!required) {
    throw new Error(`${pluginName}: unknown plugin kind ${manifest.kind}`);
  }
  if (!manifest.exports || typeof manifest.exports[required] !== "string") {
    throw new Error(`${pluginName}: missing ${required} export`);
  }
}

function assertEntryLooksLikeWasm(entryPath, pluginName) {
  const entry = fs.readFileSync(entryPath);
  const isBinaryWasm =
    entry.length >= 4 &&
    entry[0] === 0x00 &&
    entry[1] === 0x61 &&
    entry[2] === 0x73 &&
    entry[3] === 0x6d;
  const isTextComponent = entry.toString("utf8").trimStart().startsWith("(component");
  if (!isBinaryWasm && !isTextComponent) {
    throw new Error(`${pluginName}: entry is not wasm binary or text component`);
  }
}

function assertEqual(actual, expected, message) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

function assertIncludes(values, expected, message) {
  if (!values.includes(expected)) {
    throw new Error(message);
  }
}
