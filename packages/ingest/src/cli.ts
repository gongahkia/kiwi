import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { assignConfidenceTier } from "./confidence.js";
import { mergeEquivalentEntries } from "./merge-equivalent.js";
import { scrapers } from "./scrapers/index.js";
import { transformRawEntry } from "./transform.js";

function usage(): never {
  throw new Error("usage: pnpm ingest run <source>");
}

async function run(sourceName: string): Promise<string> {
  const scraper = scrapers.get(sourceName);
  if (!scraper) {
    throw new Error(`unknown scraper: ${sourceName}`);
  }

  const rawEntries = [];
  for await (const raw of scraper.fetch()) {
    rawEntries.push(raw);
  }

  const entries = mergeEquivalentEntries(rawEntries.map(transformRawEntry)).map(
    assignConfidenceTier
  );
  const date = new Date().toISOString().slice(0, 10);
  const rootDir = fileURLToPath(new URL("../../..", import.meta.url));
  const outputPath = join(rootDir, "data", "deltas", date, `${sourceName}.json`);
  const delta = {
    entries,
    generated_at: new Date().toISOString(),
    source: sourceName
  };

  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(delta, null, 2)}\n`);
  return outputPath;
}

const [, , command, sourceName] = process.argv;

try {
  if (command !== "run" || !sourceName) {
    usage();
  }

  const outputPath = await run(sourceName);
  console.log(outputPath);
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
