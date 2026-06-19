import { describe, expect, it } from "vitest";

import { createNoMatchResponse } from "./no-match.js";

describe("createNoMatchResponse", () => {
  it("returns explicit empty matches and a suggest URL", () => {
    expect(createNoMatchResponse("unknown acronym")).toEqual({
      matches: [],
      suggest_url: "/suggest?term=unknown+acronym"
    });
  });

  it("encodes the query safely", () => {
    expect(createNoMatchResponse("C++?")).toEqual({
      matches: [],
      suggest_url: "/suggest?term=C%2B%2B%3F"
    });
  });
});
