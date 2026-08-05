import { describe, expect, it } from "vitest";

import { groupDisambiguations } from "./disambiguation.js";
import type { SearchResult } from "./api.js";

function result(id: string, expansion: string, domains: string[], score: number): SearchResult {
  return {
    entry: {
      aliases: [],
      confidence_tier: "T2",
      contemporaries: [],
      domains,
      expansions: [expansion],
      id,
      layer: "public",
      meaning_short: expansion,
      sources: [],
      term: "CAP",
      term_normalized: "cap"
    },
    score,
    score_breakdown: {
      bm25: score / 2,
      rrf: score
    }
  };
}

describe("groupDisambiguations", () => {
  it("returns expansion groups sorted by score with score breakdowns", () => {
    expect(
      groupDisambiguations([
        result("cap-policy", "Common Agricultural Policy", ["policy"], 1),
        result(
          "cap-theorem",
          "Consistency Availability Partition tolerance",
          ["distributed systems"],
          2
        )
      ])
    ).toEqual([
      {
        domains: ["distributed systems"],
        entry_id: "cap-theorem",
        expansion: "Consistency Availability Partition tolerance",
        score: 2,
        score_breakdown: {
          bm25: 1,
          rrf: 2
        },
        term: "CAP"
      },
      {
        domains: ["policy"],
        entry_id: "cap-policy",
        expansion: "Common Agricultural Policy",
        score: 1,
        score_breakdown: {
          bm25: 0.5,
          rrf: 1
        },
        term: "CAP"
      }
    ]);
  });
});
