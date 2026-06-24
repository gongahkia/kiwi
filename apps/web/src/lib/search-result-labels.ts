import type { SearchEntry } from "@wat/search";

const confidenceLabels: Record<SearchEntry["confidence_tier"], string> = {
  T1: "High confidence",
  T2: "Verified",
  T3: "Low confidence",
  T4: "Pending review"
};

const layerLabels: Record<SearchEntry["layer"], string> = {
  personal: "Personal entry",
  public: "Public source",
  team: "Team entry"
};

export function confidenceLabel(tier: SearchEntry["confidence_tier"]): string {
  return confidenceLabels[tier];
}

export function layerLabel(layer: SearchEntry["layer"]): string {
  return layerLabels[layer];
}

export function sourceStatusLabel(entry: SearchEntry): string {
  if (entry.layer === "public") {
    const noun = entry.sources.length === 1 ? "source" : "sources";
    return `${entry.sources.length} ${noun}`;
  }

  const source = entry.sources[0];
  const license = source?.license ?? "unknown license";
  const quality = source?.source_quality ?? "community";
  return `User-contributed - ${license} - ${quality} source`;
}
