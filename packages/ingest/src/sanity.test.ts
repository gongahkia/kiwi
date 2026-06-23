import { describe, expect, it } from "vitest";

import { lintEntries } from "./sanity.js";

describe("lintEntries", () => {
  it("passes sourced public entries", () => {
    expect(
      lintEntries([
        {
          confidence_tier: "T2",
          sources: [
            {
              license: "MIT",
              publisher: "Example",
              retrieved_at: "2026-01-01T00:00:00.000Z",
              snippet: "",
              source_quality: "canonical",
              title: "Example",
              url: "https://example.com"
            }
          ],
          term: "API"
        }
      ])
    ).toEqual([]);
  });

  it("reports public entries without sources", () => {
    expect(lintEntries([{ term: "API" }])).toEqual([
      { code: "missing_public_source", entry_id: "API" }
    ]);
  });

  it("reports T1 entries without canonical source", () => {
    expect(
      lintEntries([
        {
          confidence_tier: "T1",
          sources: [
            {
              license: "MIT",
              publisher: "Example",
              retrieved_at: "2026-01-01T00:00:00.000Z",
              snippet: "",
              source_quality: "secondary",
              title: "Example",
              url: "https://example.com"
            }
          ],
          term: "API"
        }
      ])
    ).toEqual([{ code: "t1_without_canonical_source", entry_id: "API" }]);
  });

  it("reports contemporary self-references", () => {
    expect(lintEntries([{ contemporaries: ["Kafka"], layer: "team", term: "Kafka" }])).toEqual([
      { code: "contemporary_self_reference", entry_id: "Kafka" }
    ]);
  });

  it("reports duplicate contemporaries", () => {
    expect(
      lintEntries([{ contemporaries: ["Kafka", " kafka "], layer: "team", term: "NATS" }])
    ).toEqual([{ code: "contemporary_duplicate", entry_id: "NATS" }]);
  });

  it("reports empty contemporaries", () => {
    expect(lintEntries([{ contemporaries: [" "], layer: "team", term: "NATS" }])).toEqual([
      { code: "contemporary_empty", entry_id: "NATS" }
    ]);
  });
});
