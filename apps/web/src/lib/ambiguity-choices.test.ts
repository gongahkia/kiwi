import { describe, expect, it } from "vitest";
import type { SearchResult } from "@wat/search";

import { ambiguityChoices } from "./ambiguity-choices";

function result(
  id: string,
  expansion: string,
  domains: string[],
  layer: SearchResult["entry"]["layer"],
  confidenceTier: SearchResult["entry"]["confidence_tier"],
  score: number
): SearchResult {
  return {
    entry: {
      aliases: [],
      confidence_tier: confidenceTier,
      contemporaries: [],
      domains,
      expansions: [expansion],
      id,
      layer,
      meaning_short: expansion,
      sources: [],
      term: "CAP",
      term_normalized: "cap"
    },
    score,
    score_breakdown: { bm25: score }
  };
}

describe("ambiguityChoices", () => {
  it("returns exact-term choices with domain, layer, and confidence metadata", () => {
    expect(
      ambiguityChoices("CAP", [
        result("team-cap", "Change Approval Process", ["ops"], "team", "T4", 2),
        result("public-cap", "CAP theorem", ["distributed systems"], "public", "T2", 1)
      ])
    ).toEqual([
      {
        confidence_tier: "T4",
        domains: ["ops"],
        entry_id: "team-cap",
        expansion: "Change Approval Process",
        layer: "team",
        score: 2,
        term: "CAP"
      },
      {
        confidence_tier: "T2",
        domains: ["distributed systems"],
        entry_id: "public-cap",
        expansion: "CAP theorem",
        layer: "public",
        score: 1,
        term: "CAP"
      }
    ]);
  });

  it("hides the chooser for single meanings", () => {
    expect(
      ambiguityChoices("CAP", [result("cap", "CAP theorem", ["ds"], "public", "T2", 1)])
    ).toEqual([]);
  });
});
