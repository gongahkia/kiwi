import { readFile } from "node:fs/promises";
import { isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

import { scrapers } from "./scrapers/index.js";

export interface SourceRegistryCheck {
  extra: string[];
  missing: string[];
  ok: boolean;
}

const rootDir = fileURLToPath(new URL("../../..", import.meta.url));

export function scraperNamesFromRegistry(markdown: string): string[] {
  return Array.from(markdown.matchAll(/^\| `([^`]+)` \|/gm), (match) => match[1] ?? "").filter(
    Boolean
  );
}

export function checkSourceRegistry(
  markdown: string,
  expectedNames = Array.from(scrapers.keys()).sort()
): SourceRegistryCheck {
  const actual = new Set(scraperNamesFromRegistry(markdown));
  const expected = new Set(expectedNames);
  const missing = expectedNames.filter((name) => !actual.has(name));
  const extra = Array.from(actual).filter((name) => !expected.has(name));

  return {
    extra,
    missing,
    ok: missing.length === 0 && extra.length === 0
  };
}

async function main() {
  const registryPath = process.argv[2] ?? "docs/sources.md";
  const resolved = isAbsolute(registryPath) ? registryPath : join(rootDir, registryPath);
  const result = checkSourceRegistry(await readFile(resolved, "utf8"));
  if (!result.ok) {
    for (const name of result.missing) console.error(`missing scraper registry row: ${name}`);
    for (const name of result.extra) console.error(`unknown scraper registry row: ${name}`);
    process.exitCode = 1;
    return;
  }

  console.log(`source registry ok: ${scrapers.size} scrapers documented`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  void main();
}
