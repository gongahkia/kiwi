import type { ConfidenceTier, SourceCitation } from "./schema.js";

export interface ConfidenceTierInput {
  sources: Array<Pick<SourceCitation, "source_quality">>;
  userContributed?: boolean;
}

export function resolveConfidenceTier(input: ConfidenceTierInput): ConfidenceTier {
  if (input.userContributed) {
    return "T4";
  }

  const canonicalSources = input.sources.filter((source) => source.source_quality === "canonical");
  if (canonicalSources.length >= 2) {
    return "T1";
  }

  if (canonicalSources.length === 1) {
    return "T2";
  }

  if (input.sources.length > 0) {
    return "T3";
  }

  return "T4";
}
