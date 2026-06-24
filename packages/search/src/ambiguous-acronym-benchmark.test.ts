import { describe, expect, it } from "vitest";

import benchmark from "../fixtures/ambiguous-acronyms.json" with { type: "json" };
import { searchHybrid, type HybridSearchCandidate } from "./hybrid.js";

interface AmbiguousAcronymCase {
  candidates: HybridSearchCandidate[];
  expected_id: string;
  query: string;
}

const cases = benchmark as AmbiguousAcronymCase[];

describe("ambiguous acronym benchmark", () => {
  it("covers CAP/API/ACL and related overloaded tech acronyms", () => {
    const terms = new Set(
      cases.flatMap((caseItem) => caseItem.candidates.map((item) => item.term))
    );

    expect(terms).toEqual(new Set(["ACL", "API", "CAP", "CSP", "CSR", "IR"]));
  });

  it.each(cases)("ranks $expected_id first for '$query'", ({ candidates, expected_id, query }) => {
    const matches = searchHybrid(query, candidates, { limit: 5 });

    expect(matches[0]?.candidate.id).toBe(expected_id);
  });
});
