import { describe, expect, it } from "vitest";

import { applyDomainContextBoost } from "./boost.js";
import type { SearchResult } from "./api.js";

const capTheorem: SearchResult = {
  entry: {
    aliases: [],
    confidence_tier: "T2",
    contemporaries: [],
    domains: ["distributed systems"],
    expansions: ["Consistency Availability Partition tolerance"],
    id: "cap-theorem",
    layer: "public",
    meaning_short: "A consistency availability partition-tolerance tradeoff.",
    sources: [],
    term: "CAP",
    term_normalized: "cap"
  },
  score: 1,
  score_breakdown: {}
};

const capPolicy: SearchResult = {
  entry: {
    aliases: [],
    confidence_tier: "T2",
    contemporaries: [],
    domains: ["policy"],
    expansions: ["Common Agricultural Policy"],
    id: "cap-policy",
    layer: "public",
    meaning_short: "European agricultural policy.",
    sources: [],
    term: "CAP",
    term_normalized: "cap"
  },
  score: 1.2,
  score_breakdown: {}
};

describe("applyDomainContextBoost", () => {
  it("raises CAP theorem above CAP agricultural policy for distributed systems context", () => {
    const [top] = applyDomainContextBoost([capPolicy, capTheorem], {
      context: "distributed systems consistency partition tolerance",
      query: "CAP"
    });

    expect(top?.entry.id).toBe("cap-theorem");
  });
});
