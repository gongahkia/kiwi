import { existsSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(new URL("../package.json", import.meta.url)));

for (const relative of ["wasm/.gitignore", "wasm/package.json", "wasm/kumeyuri_render_wasm_bg.wasm.d.ts"]) {
  rmSync(join(root, relative), { force: true });
}

for (const relative of [
  "wasm/kumeyuri_render_wasm.d.ts",
  "wasm/kumeyuri_render_wasm.js",
  "wasm/kumeyuri_render_wasm_bg.wasm",
]) {
  if (!existsSync(join(root, relative))) {
    throw new Error(`missing required package file: ${relative}`);
  }
}
