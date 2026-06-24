import type { SearchEntry } from "@wat/search";

import type { ApiIdentity } from "@/lib/api-identity";
import { getPersonalEntries } from "@/lib/personal-entries";
import { getPublicCorpusEntries } from "@/lib/public-corpus";
import { getTeamEntries, type TeamEntry } from "@/lib/team-entries";
import { getTeamMember } from "@/lib/team-members";

export async function getPublicEntries(): Promise<SearchEntry[]> {
  return getPublicCorpusEntries();
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
