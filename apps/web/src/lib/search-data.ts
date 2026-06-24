import { readFile } from "node:fs/promises";
import { join } from "node:path";

import type { SearchEntry } from "@wat/search";

import type { ApiIdentity } from "@/lib/api-identity";
import { getPersonalEntries } from "@/lib/personal-entries";
import { getTeamEntries, type TeamEntry } from "@/lib/team-entries";
import { getTeamMember } from "@/lib/team-members";

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

export async function getPublicEntries(): Promise<SearchEntry[]> {
  const parsed = JSON.parse(await readSeedJson()) as { entries: SearchEntry[] };
  return parsed.entries.filter((entry) => entry.layer === "public");
}

export function getScopedTeamEntries(identity: ApiIdentity): SearchEntry[] {
  if (identity.type !== "api") return [];
  const member = identity.userId ? getTeamMember(identity.userId) : null;
  if (!member && !identity.teamId) return [];

  return getTeamEntries().map((entry) => layeredEntryToSearchEntry(entry, "team"));
}

export function getScopedPersonalEntries(identity: ApiIdentity): SearchEntry[] {
  if (identity.type !== "api" || !identity.userId) return [];

  return getPersonalEntries(identity.userId).map((entry) =>
    layeredEntryToSearchEntry(entry, "personal")
  );
}

function layeredEntryToSearchEntry(entry: TeamEntry, layer: "personal" | "team"): SearchEntry {
  return {
    aliases: [],
    confidence_tier: "T4",
    contemporaries: entry.contemporaries ?? [],
    domains: entry.domains,
    expansions: [entry.expansion],
    id: entry.id,
    layer,
    meaning_short: entry.meaning,
    sources: entry.sources.map((source) => ({ ...source, source_quality: "community" })),
    term: entry.term,
    term_normalized: entry.term.trim().toLowerCase()
  };
}
