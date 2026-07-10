import { describe, expect, it } from "vitest";

import { acronymDensityForText, heatmapAlpha } from "./acronym-heatmap.js";

describe("acronym heatmap", () => {
  it("scores acronym density by count and ratio", () => {
    expect(acronymDensityForText("no uppercase jargon here")).toMatchObject({
      count: 0,
      level: 0
    });
    expect(acronymDensityForText("API owners review TLS and SLO docs")).toMatchObject({
      count: 3,
      level: 3
    });
    expect(
      acronymDensityForText(
        "This paragraph mentions API once among many ordinary words in a longer sentence."
      )
    ).toMatchObject({
      count: 1,
      level: 1
    });
  });

  it("maps density levels to stable overlay alpha values", () => {
    expect([0, 1, 2, 3].map((level) => heatmapAlpha(level as 0 | 1 | 2 | 3))).toEqual([
      "0",
      "0.1",
      "0.18",
      "0.26"
    ]);
  });
});
