import { describe, expect, it } from "vitest";

import { detectAcronymCollisions } from "./collisions.js";

describe("detectAcronymCollisions", () => {
  it("reports same-acronym different-domain pairs", () => {
    expect(
      detectAcronymCollisions([
        { domains: ["distributed systems"], id: "cap-theorem", term_normalized: "cap" },
        { domains: ["policy"], id: "cap-policy", term_normalized: "cap" }
      ])
    ).toEqual([
      {
        domains: ["distributed systems", "policy"],
        ids: ["cap-theorem", "cap-policy"],
        term_normalized: "cap"
      }
    ]);
  });

  it("ignores same-domain duplicates", () => {
    expect(
      detectAcronymCollisions([
        { domains: ["web"], term_normalized: "api" },
        { domains: ["web"], term_normalized: "api" }
      ])
    ).toEqual([]);
  });
});
