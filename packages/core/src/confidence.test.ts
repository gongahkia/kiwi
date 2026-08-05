import { describe, expect, it } from "vitest";

import { resolveConfidenceTier } from "./confidence.js";

describe("resolveConfidenceTier", () => {
  it("returns T1 for multi-source canonical agreement", () => {
    expect(
      resolveConfidenceTier({
        sources: [{ source_quality: "canonical" }, { source_quality: "canonical" }]
      })
    ).toBe("T1");
  });

  it("returns T2 for one canonical source", () => {
    expect(resolveConfidenceTier({ sources: [{ source_quality: "canonical" }] })).toBe("T2");
  });

  it("returns T3 for sourced non-canonical entries", () => {
    expect(
      resolveConfidenceTier({
        sources: [{ source_quality: "secondary" }, { source_quality: "community" }]
      })
    ).toBe("T3");
  });

  it("returns T4 for user-contributed entries", () => {
    expect(
      resolveConfidenceTier({
        sources: [{ source_quality: "canonical" }, { source_quality: "canonical" }],
        userContributed: true
      })
    ).toBe("T4");
  });

  it("returns T4 for unsourced entries", () => {
    expect(resolveConfidenceTier({ sources: [] })).toBe("T4");
  });
});
