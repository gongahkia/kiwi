import type { CanonicalEntry } from "./transform.js";

export interface AcronymCollision {
  domains: string[];
  ids: string[];
  term_normalized: string;
}

export function detectAcronymCollisions(
  entries: Array<Pick<CanonicalEntry, "domains" | "term_normalized"> & { id?: string }>
): AcronymCollision[] {
  const byTerm = new Map<string, Array<Pick<CanonicalEntry, "domains"> & { id?: string }>>();

  for (const entry of entries) {
    const group = byTerm.get(entry.term_normalized) ?? [];
    group.push(entry);
    byTerm.set(entry.term_normalized, group);
  }

  return Array.from(byTerm.entries()).flatMap(([termNormalized, group]) => {
    const domains = Array.from(new Set(group.flatMap((entry) => entry.domains))).sort();
    if (group.length < 2 || domains.length < 2) {
      return [];
    }

    return [
      {
        domains,
        ids: group.map((entry, index) => entry.id ?? `${termNormalized}-${index}`),
        term_normalized: termNormalized
      }
    ];
  });
}
