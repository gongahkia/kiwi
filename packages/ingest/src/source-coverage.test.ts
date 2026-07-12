import { describe, expect, it } from "vitest";

import { checkSourceCoverage } from "./source-coverage.js";

describe("checkSourceCoverage", () => {
  it("rejects public entries without acceptable provenance", () => {
    expect(
      checkSourceCoverage({
        entries: [{ confidence_tier: "T2", id: "api", layer: "public", sources: [] }]
      })
    ).toEqual([{ entryId: "api", reason: "missing acceptable provenance" }]);
  });

  it("treats normalized delta entries without a layer as public", () => {
    expect(checkSourceCoverage({ entries: [{ term: "API", sources: [] }] })).toEqual([
      { entryId: "API", reason: "missing acceptable provenance" }
    ]);
  });

  it("allows unsourced public entries only when marked review-only", () => {
    expect(
      checkSourceCoverage({
        entries: [{ confidence_tier: "T4", id: "api", layer: "public", sources: [] }]
      })
    ).toEqual([]);
  });

  it("rejects incomplete source metadata on normal public entries", () => {
    expect(
      checkSourceCoverage({
        entries: [
          {
            confidence_tier: "T1",
            id: "api",
            layer: "public",
            sources: [{ license: "MIT" }]
          }
        ]
      })
    ).toEqual([{ entryId: "api", reason: "source 0 missing url" }]);
  });
});
