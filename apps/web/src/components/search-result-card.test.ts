import { describe, expect, it } from "vitest";

import { confidenceLabel, layerLabel } from "@/lib/search-result-labels";

describe("search result card labels", () => {
  it("explains every result layer", () => {
    expect(layerLabel("public")).toBe("Public source");
    expect(layerLabel("team")).toBe("Team entry");
    expect(layerLabel("personal")).toBe("Personal entry");
  });

  it("explains confidence and pending states", () => {
    expect(confidenceLabel("T1")).toBe("High confidence");
    expect(confidenceLabel("T2")).toBe("Verified");
    expect(confidenceLabel("T3")).toBe("Low confidence");
    expect(confidenceLabel("T4")).toBe("Pending review");
  });
});
