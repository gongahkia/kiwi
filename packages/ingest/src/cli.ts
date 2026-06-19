import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

import { assignConfidenceTier } from "./confidence.js";
import { detectAcronymCollisions } from "./collisions.js";
import { mergeEquivalentEntries } from "./merge-equivalent.js";
import { scrapers } from "./scrapers/index.js";
import { transformRawEntry } from "./transform.js";

function usage(): never {
  throw new Error("usage: pnpm ingest run <source> | pnpm ingest lint --collisions <delta-json>");
}

const rootDir = fileURLToPath(new URL("../../..", import.meta.url));

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
  if (command === "run" && sourceName) {
    const outputPath = await run(sourceName);
    console.log(outputPath);
  } else if (command === "lint" && sourceName === "--collisions") {
    const inputPath = process.argv[4];
    if (!inputPath) {
      usage();
    }
    const resolvedInputPath = isAbsolute(inputPath) ? inputPath : join(rootDir, inputPath);
    const parsed = JSON.parse(await readFile(resolvedInputPath, "utf8")) as {
      entries: Parameters<typeof detectAcronymCollisions>[0];
    };
    console.log(JSON.stringify(detectAcronymCollisions(parsed.entries), null, 2));
  } else {
    usage();
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
