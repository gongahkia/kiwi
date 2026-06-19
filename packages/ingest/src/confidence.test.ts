import { describe, expect, it } from "vitest";

import { assignConfidenceTier, type ConfidenceTier } from "./confidence.js";
import { transformRawEntry } from "./transform.js";

function entry(index: number, expected: ConfidenceTier) {
  const sourceByTier = {
    T1: [
      {
        license: "MIT",
        publisher: "Canonical A",
        retrieved_at: "2026-01-01T00:00:00.000Z",
        source_quality: "canonical" as const,
        url: `https://example.com/${index}/a`
      },
      {
        license: "MIT",
        publisher: "Canonical B",
        retrieved_at: "2026-01-02T00:00:00.000Z",
        source_quality: "canonical" as const,
        url: `https://example.com/${index}/b`
      }
    ],
    T2: [
      {
        license: "MIT",
        publisher: "Canonical",
        retrieved_at: "2026-01-01T00:00:00.000Z",
        source_quality: "canonical" as const,
        url: `https://example.com/${index}/canonical`
      }
    ],
    T3: [
      {
        license: "MIT",
        publisher: "Community",
        retrieved_at: "2026-01-01T00:00:00.000Z",
        source_quality: "community" as const,
        url: `https://example.com/${index}/community`
      }
    ],
    T4: []
  };

  return {
    expected,
    input: transformRawEntry({
      expansion: `Expansion ${index}`,
      sources: sourceByTier[expected],
      term: `TERM${index}`
    })
  };
}

describe("assignConfidenceTier", () => {
  it("tiers entries correctly on a 50-entry test set", () => {
    const cases = [
      ...Array.from({ length: 10 }, (_, index) => entry(index, "T1")),
      ...Array.from({ length: 10 }, (_, index) => entry(index + 10, "T2")),
      ...Array.from({ length: 15 }, (_, index) => entry(index + 20, "T3")),
      ...Array.from({ length: 15 }, (_, index) => entry(index + 35, "T4"))
    ];

    expect(cases).toHaveLength(50);
    for (const item of cases) {
      expect(assignConfidenceTier(item.input).confidence_tier).toBe(item.expected);
    }
  });
});
