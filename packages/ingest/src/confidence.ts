import type { CanonicalEntry } from "./transform.js";

export type ConfidenceTier = "T1" | "T2" | "T3" | "T4";

export interface TieredCanonicalEntry extends CanonicalEntry {
  confidence_tier: ConfidenceTier;
}

export function resolveIngestConfidenceTier(entry: CanonicalEntry): ConfidenceTier {
  const canonicalCount = entry.sources.filter(
    (source) => source.source_quality === "canonical"
  ).length;
  if (canonicalCount >= 2) {
    return "T1";
  }

  if (canonicalCount === 1) {
    return "T2";
  }

  if (entry.sources.length > 0) {
    return "T3";
  }

  return "T4";
}

export function assignConfidenceTier(entry: CanonicalEntry): TieredCanonicalEntry {
  return {
    ...entry,
    confidence_tier: resolveIngestConfidenceTier(entry)
  };
}
