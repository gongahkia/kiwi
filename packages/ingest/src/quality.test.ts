import { describe, expect, it } from "vitest";

import { filterGarbageRawEntries } from "./quality.js";
import type { RawEntry } from "./scraper.js";

function raw(term: string, expansion?: string): RawEntry {
  return {
    expansion,
    sources: [
      {
        license: "MIT",
        publisher: "Example",
        retrieved_at: "2026-01-01T00:00:00.000Z",
        url: "https://example.com"
      }
    ],
    term
  };
}

describe("filterGarbageRawEntries", () => {
  it("rejects entries lacking expansion text", () => {
    const result = filterGarbageRawEntries([raw("API")]);

    expect(result.accepted).toHaveLength(0);
    expect(result.rejected[0]?.reason).toBe("missing_expansion");
  });

  it("rejects entries with term length below 2", () => {
    const result = filterGarbageRawEntries([raw("A", "Application")]);

    expect(result.accepted).toHaveLength(0);
    expect(result.rejected[0]?.reason).toBe("term_too_short");
  });

  it("rejects entries with expansion length below 2", () => {
    const result = filterGarbageRawEntries([raw("API", "A")]);

    expect(result.accepted).toHaveLength(0);
    expect(result.rejected[0]?.reason).toBe("expansion_too_short");
  });

  it("accepts valid raw entries", () => {
    const result = filterGarbageRawEntries([raw("API", "Application Programming Interface")]);

    expect(result.accepted).toHaveLength(1);
    expect(result.rejected).toHaveLength(0);
  });
});
