import { describe, expect, it } from "vitest";

import corpus from "../fixtures/dev-tooling-acronyms.json" with { type: "json" };

describe("dev tooling acronym benchmark corpus", () => {
  it("has 500 sourced query-answer fixtures", () => {
    expect(corpus).toHaveLength(500);
    expect(new Set(corpus.map((entry) => entry.query))).toHaveLength(500);

    for (const entry of corpus) {
      expect(entry.query).toMatch(/\S/);
      expect(entry.expected_answer).toMatch(/\S/);
      expect(entry.source_url).toMatch(/^https:\/\/github\.com\//);
      expect(entry.source_license).toBe("CC0-1.0");
    }
  });
});
