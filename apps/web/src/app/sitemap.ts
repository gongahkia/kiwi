import { readFile } from "node:fs/promises";
import { join } from "node:path";

import type { MetadataRoute } from "next";

interface PublicEntry {
  id: string;
  layer: string;
  updated_at: string;
}

async function getPublicEntries(): Promise<PublicEntry[]> {
  const seedJson = await readSeedJson();
  const parsed = JSON.parse(seedJson) as { entries: PublicEntry[] };
  return parsed.entries.filter((entry) => entry.layer === "public");
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

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
  const entries = await getPublicEntries();

  return [
    {
      url: siteUrl,
      lastModified: new Date()
    },
    ...entries.map((entry) => ({
      url: `${siteUrl}/term/${entry.id}`,
      lastModified: new Date(entry.updated_at)
    }))
  ];
}
