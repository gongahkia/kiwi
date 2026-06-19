import { describe, expect, it } from "vitest";

import manualSeeds from "../../ingest/seeds/manual.json" with { type: "json" };
import { validateEntries, validateEntry } from "./entry-validator.js";

const manualSeed = validateEntries(manualSeeds.entries)[0]!;

describe("validateEntry", () => {
  it("validates all manual seed entries", () => {
    expect(validateEntries(manualSeeds.entries)).toHaveLength(50);
  });

  it("requires normalized terms to match the entry term", () => {
    expect(() =>
      validateEntry({
        ...manualSeed,
        term_normalized: "wrong"
      })
    ).toThrow(/term_normalized/);
  });

  it("requires sourced public entries", () => {
    expect(() =>
      validateEntry({
        ...manualSeed,
        sources: []
      })
    ).toThrow(/public entries/);
  });

  it("requires canonical source evidence for T1 entries", () => {
    expect(() =>
      validateEntry({
        ...manualSeed,
        sources: manualSeed.sources.map((source) => ({
          ...source,
          source_quality: "secondary"
        }))
      })
    ).toThrow(/T1 entries/);
  });

  it("requires team ids only for team entries", () => {
    expect(() =>
      validateEntry({
        ...manualSeed,
        layer: "team",
        team_id: null
      })
    ).toThrow(/team entries/);

    expect(() =>
      validateEntry({
        ...manualSeed,
        team_id: "team_1"
      })
    ).toThrow(/public entries/);
  });
});
