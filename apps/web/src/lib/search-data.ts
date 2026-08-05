import type { SearchEntry, SearchSource } from "@wat/search";

import type { ApiIdentity } from "@/lib/api-identity";
import { authDb } from "@/lib/auth-db";
import { getPersonalEntries } from "@/lib/personal-entries";
import { getPublicCorpusEntries } from "@/lib/public-corpus";
import type { WatSessionUser } from "@/lib/session";
import { getTeamEntries, type TeamEntry } from "@/lib/team-entries";

type PublicEntryRow = {
  aliases: string[];
  confidence_tier: SearchEntry["confidence_tier"];
  contemporaries: string[];
  domains: string[];
  expansions: string[];
  id: string;
  meaning_short: string;
  term: string;
  term_normalized: string;
};

type PublicSourceRow = {
  entry_id: string;
  license: string;
  publisher: string;
  retrieved_at: Date;
  snippet: string;
  source_quality: SearchSource["source_quality"];
  title: string;
  url: string;
};

export async function getPublicEntries(): Promise<SearchEntry[]> {
  if (process.env.NODE_ENV === "test") return getPublicCorpusEntries();
  const { rows } = await authDb().query<PublicEntryRow>(
    `
    select id, term, term_normalized, expansions, domains, meaning_short,
      confidence_tier, aliases, contemporaries
    from entries
    where layer = 'public' and deprecated = false
    order by term_normalized, id
    `
  );
  if (rows.length === 0) return [];
  const { rows: sources } = await authDb().query<PublicSourceRow>(
    `
    select entry_id, url, title, publisher, license, retrieved_at, snippet, source_quality
    from sources
    where entry_id = any($1::text[])
    order by entry_id, position
    `,
    [rows.map((row) => row.id)]
  );
  const sourcesByEntry = new Map<string, SearchSource[]>();
  for (const source of sources) {
    const entrySources = sourcesByEntry.get(source.entry_id) ?? [];
    entrySources.push({
      license: source.license,
      publisher: source.publisher,
      retrieved_at: source.retrieved_at.toISOString(),
      snippet: source.snippet,
      source_quality: source.source_quality,
      title: source.title,
      url: source.url
    });
    sourcesByEntry.set(source.entry_id, entrySources);
  }
  return rows.map((row) => ({
    aliases: row.aliases,
    confidence_tier: row.confidence_tier,
    contemporaries: row.contemporaries,
    domains: row.domains,
    expansions: row.expansions,
    id: row.id,
    layer: "public",
    meaning_short: row.meaning_short,
    sources: sourcesByEntry.get(row.id) ?? [],
    term: row.term,
    term_normalized: row.term_normalized
  }));
}

export async function getScopedTeamEntries(identity: ApiIdentity): Promise<SearchEntry[]> {
  if (identity.type !== "api" || !identity.teamId) return [];
  return (await getTeamEntries(identity.teamId)).map((entry) =>
    layeredEntryToSearchEntry(entry, "team")
  );
}

export async function getScopedPersonalEntries(identity: ApiIdentity): Promise<SearchEntry[]> {
  if (identity.type !== "api" || !identity.userId) return [];
  return (await getPersonalEntries(identity.userId)).map((entry) =>
    layeredEntryToSearchEntry(entry, "personal")
  );
}

export async function getVisibleEntriesForSession(
  session: WatSessionUser | null
): Promise<SearchEntry[]> {
  const [publicEntries, teamEntries, personalEntries] = await Promise.all([
    getPublicEntries(),
    session?.teamId ? getTeamEntries(session.teamId) : [],
    session ? getPersonalEntries(session.id) : []
  ]);

  return [
    ...publicEntries,
    ...teamEntries.map((entry) => layeredEntryToSearchEntry(entry, "team")),
    ...personalEntries.map((entry) => layeredEntryToSearchEntry(entry, "personal"))
  ];
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
