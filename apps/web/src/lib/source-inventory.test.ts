import { describe, expect, it } from "vitest";

import { sourceInventoryFromEntries } from "./source-inventory";

describe("source inventory", () => {
  it("summarizes public sources with policy and status", () => {
    expect(
      sourceInventoryFromEntries([
        {
          layer: "public",
          sources: [
            {
              license: "CC-BY-4.0",
              publisher: "MDN",
              retrieved_at: "2026-06-24T00:00:00.000Z",
              title: "API",
              url: "https://developer.mozilla.org/docs/Glossary/API"
            }
          ]
        },
        {
          layer: "team",
          sources: [
            {
              license: "proprietary-team",
              publisher: "Team",
              retrieved_at: "2026-06-24T00:00:00.000Z",
              title: "Private",
              url: "https://example.com/private"
            }
          ]
        }
      ])
    ).toEqual([
      {
        count: 1,
        failure_status: "ok",
        license: "CC-BY-4.0",
        license_policy: "compatible public corpus license",
        publisher: "MDN",
        retrieved_at: "2026-06-24T00:00:00.000Z",
        title: "API",
        url: "https://developer.mozilla.org/docs/Glossary/API"
      }
    ]);
  });

  it("marks sources that need review", () => {
    expect(
      sourceInventoryFromEntries([
        {
          layer: "public",
          sources: [
            {
              license: "CC-BY-NC-ND-4.0",
              publisher: "Example",
              retrieved_at: "not a date",
              title: "Bad",
              url: "https://example.com/bad"
            }
          ]
        }
      ])[0]
    ).toMatchObject({
      failure_status: "invalid retrieved_at",
      license_policy: "manual review required"
    });
  });
});
