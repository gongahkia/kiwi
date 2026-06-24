import { describe, expect, it } from "vitest";

import { mergeEquivalentEntries } from "./merge-equivalent.js";
import { transformRawEntry } from "./transform.js";

describe("mergeEquivalentEntries", () => {
  it("merges CAP from Wikipedia and textbook into one multi-source entry", () => {
    const entries = [
      transformRawEntry({
        aliases: ["partition tolerance theorem"],
        contemporaries: ["PACELC"],
        domains: ["distributed systems"],
        expansion: "Consistency Availability Partition tolerance",
        sources: [
          {
            license: "CC-BY-SA-4.0",
            publisher: "Wikipedia",
            retrieved_at: "2026-01-01T00:00:00.000Z",
            title: "CAP theorem",
            url: "https://en.wikipedia.org/wiki/CAP_theorem"
          }
        ],
        term: "CAP"
      }),
      transformRawEntry({
        aliases: ["Brewer theorem"],
        contemporaries: ["Jepsen"],
        domains: ["databases"],
        expansion: "Consistency Availability Partition tolerance",
        sources: [
          {
            license: "MIT",
            publisher: "Distributed Systems Textbook",
            retrieved_at: "2026-01-02T00:00:00.000Z",
            title: "CAP chapter",
            url: "https://example.com/cap-textbook"
          }
        ],
        term: "CAP"
      })
    ];

    const merged = mergeEquivalentEntries(entries);

    expect(merged).toHaveLength(1);
    expect(merged[0]?.sources.map((source) => source.url)).toEqual([
      "https://en.wikipedia.org/wiki/CAP_theorem",
      "https://example.com/cap-textbook"
    ]);
    expect(merged[0]?.aliases).toEqual(["partition tolerance theorem", "Brewer theorem"]);
    expect(merged[0]?.contemporaries).toEqual(["PACELC", "Jepsen"]);
    expect(merged[0]?.domains).toEqual(["distributed systems", "databases"]);
  });

  it("keeps non-equivalent entries separate", () => {
    const entries = [
      transformRawEntry({ expansion: "Common Agricultural Policy", sources: [], term: "CAP" }),
      transformRawEntry({
        expansion: "Consistency Availability Partition tolerance",
        sources: [],
        term: "CAP"
      })
    ];

    expect(mergeEquivalentEntries(entries)).toHaveLength(2);
  });
});
