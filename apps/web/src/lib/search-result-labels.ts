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
