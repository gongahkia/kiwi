import type { CanonicalEntry } from "./transform.js";

export interface SourceProvenance {
  retrieved_at: string;
  url: string;
}

export function getEntryProvenance(entry: CanonicalEntry): SourceProvenance[] {
  return entry.sources.map((source) => ({
    retrieved_at: source.retrieved_at,
    url: source.url
  }));
}

export function hasCompleteProvenance(entry: CanonicalEntry): boolean {
  return getEntryProvenance(entry).every(
    (source) => source.url.length > 0 && source.retrieved_at.length > 0
  );
}
