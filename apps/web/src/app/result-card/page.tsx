import { readFile } from "node:fs/promises";
import { join } from "node:path";

import type { SearchEntry } from "@wat/search";

import { SearchResultCard } from "@/components/search-result-card";

async function getSampleEntry(): Promise<SearchEntry> {
  const seedJson = await readSeedJson();
  const parsed = JSON.parse(seedJson) as { entries: SearchEntry[] };
  return parsed.entries.find((entry) => entry.id === "seed-api-application-programming-interface")!;
}

async function readSeedJson(): Promise<string> {
  for (const seedPath of [
    join(process.cwd(), "packages/ingest/seeds/manual.json"),
    join(process.cwd(), "../../packages/ingest/seeds/manual.json")
  ]) {
    try {
      return await readFile(seedPath, "utf8");
    } catch {
      continue;
    }
  }

  throw new Error("manual seed file not found");
}

export default async function ResultCardPage() {
  const entry = await getSampleEntry();

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <section className="mx-auto grid max-w-2xl gap-4">
        <h1 className="text-3xl font-semibold">Result card</h1>
        <SearchResultCard entry={entry} />
      </section>
    </main>
  );
}
