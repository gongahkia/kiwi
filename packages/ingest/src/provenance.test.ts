import { describe, expect, it } from "vitest";

import { mergeEquivalentEntries } from "./merge-equivalent.js";
import { getEntryProvenance, hasCompleteProvenance } from "./provenance.js";
import { transformRawEntry } from "./transform.js";

describe("provenance tracking", () => {
  it("retains source URLs and retrieval timestamps for every entry", () => {
    const entry = transformRawEntry({
      expansion: "Service Level Agreement",
      sources: [
        {
          license: "MIT",
          publisher: "Example",
          retrieved_at: "2026-01-01T00:00:00.000Z",
          url: "https://example.com/sla"
        }
      ],
      term: "SLA"
    });

    expect(getEntryProvenance(entry)).toEqual([
      {
        retrieved_at: "2026-01-01T00:00:00.000Z",
        url: "https://example.com/sla"
      }
    ]);
    expect(hasCompleteProvenance(entry)).toBe(true);
  });

  it("retains provenance after equivalent-source merge", () => {
    const [entry] = mergeEquivalentEntries([
      transformRawEntry({
        expansion: "Service Level Agreement",
        sources: [
          {
            license: "MIT",
            publisher: "Example A",
            retrieved_at: "2026-01-01T00:00:00.000Z",
            url: "https://example.com/a"
          }
        ],
        term: "SLA"
      }),
      transformRawEntry({
        expansion: "Service Level Agreement",
        sources: [
          {
            license: "MIT",
            publisher: "Example B",
            retrieved_at: "2026-01-02T00:00:00.000Z",
            url: "https://example.com/b"
          }
        ],
        term: "SLA"
      })
    ]);

    expect(entry ? getEntryProvenance(entry) : []).toEqual([
      {
        retrieved_at: "2026-01-01T00:00:00.000Z",
        url: "https://example.com/a"
      },
      {
        retrieved_at: "2026-01-02T00:00:00.000Z",
        url: "https://example.com/b"
      }
    ]);
  });
});
