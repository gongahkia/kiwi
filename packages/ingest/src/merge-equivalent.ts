import type { CanonicalEntry, CanonicalSourceCitation } from "./transform.js";

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values));
}

function mergeSources(
  left: CanonicalSourceCitation[],
  right: CanonicalSourceCitation[]
): CanonicalSourceCitation[] {
  const byUrl = new Map<string, CanonicalSourceCitation>();
  for (const source of [...left, ...right]) {
    byUrl.set(source.url, source);
  }
  return Array.from(byUrl.values());
}

export function mergeEquivalentEntries(entries: CanonicalEntry[]): CanonicalEntry[] {
  const byKey = new Map<string, CanonicalEntry>();

  for (const entry of entries) {
    const existing = byKey.get(entry.dedup_key);
    if (!existing) {
      byKey.set(entry.dedup_key, structuredClone(entry));
      continue;
    }

    byKey.set(entry.dedup_key, {
      ...existing,
      domains: uniqueStrings([...existing.domains, ...entry.domains]),
      examples: uniqueStrings([...existing.examples, ...entry.examples]),
      sources: mergeSources(existing.sources, entry.sources)
    });
  }

  return Array.from(byKey.values());
}
