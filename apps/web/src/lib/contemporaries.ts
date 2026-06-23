import type { SearchEntry } from "@wat/search";

import type { ApiIdentity } from "@/lib/api-identity";
import {
  getPublicEntries,
  getScopedPersonalEntries,
  getScopedTeamEntries
} from "@/lib/search-data";

export interface ResolvedContemporary {
  id: string | null;
  meaning_short: string | null;
  term: string;
}

export interface ContemporaryLookupEntry {
  aliases: string[];
  id: string;
  meaning_short: string;
  term: string;
  term_normalized: string;
}

function normalizeKey(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}\s]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export async function getVisibleSearchEntries(identity: ApiIdentity): Promise<SearchEntry[]> {
  return [
    ...(await getPublicEntries()),
    ...getScopedTeamEntries(identity),
    ...getScopedPersonalEntries(identity)
  ];
}

export function resolveContemporaryTerms(
  contemporaries: string[],
  entries: ContemporaryLookupEntry[]
): ResolvedContemporary[] {
  const byName = new Map<string, ContemporaryLookupEntry>();

  for (const entry of entries) {
    byName.set(normalizeKey(entry.term), entry);
    byName.set(normalizeKey(entry.term_normalized), entry);
    for (const alias of entry.aliases) {
      byName.set(normalizeKey(alias), entry);
    }
  }

  return contemporaries.map((term) => {
    const resolved = byName.get(normalizeKey(term));

    return {
      id: resolved?.id ?? null,
      meaning_short: resolved?.meaning_short ?? null,
      term
    };
  });
}

export async function resolveEntryContemporaries(
  entryId: string,
  identity: ApiIdentity
): Promise<ResolvedContemporary[]> {
  const entries = await getVisibleSearchEntries(identity);
  const entry = entries.find((candidate) => candidate.id === entryId);

  return entry ? resolveContemporaryTerms(entry.contemporaries, entries) : [];
}
