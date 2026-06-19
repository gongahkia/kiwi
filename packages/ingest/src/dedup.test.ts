import { describe, expect, it } from "vitest";

import { dedupCanonicalEntries, fuzzySimilarity } from "./dedup.js";
import { transformRawEntry } from "./transform.js";

function raw(term: string, expansion: string) {
  return transformRawEntry({
    expansion,
    sources: [
      {
        license: "MIT",
        publisher: "Example",
        retrieved_at: "2026-01-01T00:00:00.000Z",
        url: `https://example.com/${term}`
      }
    ],
    term
  });
}

describe("dedupCanonicalEntries", () => {
  it("produces zero duplicates when ingestion runs twice", () => {
    const firstRun = [raw("CAP", "Consistency Availability Partition tolerance")];
    const secondRun = [raw("CAP", "Consistency Availability Partition tolerance")];

    expect(dedupCanonicalEntries([...firstRun, ...secondRun])).toHaveLength(1);
  });

  it("deduplicates fuzzy-equivalent expansions for the same normalized term", () => {
    const entries = [
      raw("CAP", "Consistency Availability Partition tolerance"),
      raw("CAP", "Consistency, Availability, and Partition tolerance")
    ];

    expect(dedupCanonicalEntries(entries, 0.8)).toHaveLength(1);
  });

  it("keeps different expansions for the same acronym", () => {
    const entries = [
      raw("CAP", "Consistency Availability Partition tolerance"),
      raw("CAP", "Common Agricultural Policy")
    ];

    expect(dedupCanonicalEntries(entries, 0.8)).toHaveLength(2);
  });

  it("scores identical strings at 1", () => {
    expect(fuzzySimilarity("api", "api")).toBe(1);
  });
});
