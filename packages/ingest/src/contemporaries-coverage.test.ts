import { describe, expect, it } from "vitest";

import { calculateContemporariesCoverage } from "./contemporaries-coverage.js";

describe("calculateContemporariesCoverage", () => {
  it("counts public target-domain entries with contemporaries", () => {
    expect(
      calculateContemporariesCoverage([
        {
          contemporaries: ["Pulumi"],
          domains: ["devops"],
          id: "terraform",
          layer: "public"
        },
        {
          contemporaries: [],
          domains: ["storage"],
          id: "volume",
          layer: "public"
        },
        {
          contemporaries: [],
          domains: ["web"],
          id: "api",
          layer: "public"
        },
        {
          contemporaries: ["Terraform"],
          domains: ["devops"],
          id: "team-iac",
          layer: "team"
        }
      ])
    ).toEqual({
      coveragePct: 50,
      targetDomains: ["cloud", "devops", "observability", "storage"],
      total: 2,
      withContemporaries: 1
    });
  });

  it("passes empty target sets as complete", () => {
    expect(calculateContemporariesCoverage([]).coveragePct).toBe(100);
  });
});
