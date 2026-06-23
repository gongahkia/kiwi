import { describe, expect, it } from "vitest";

import manualSeeds from "../../ingest/seeds/manual.json" with { type: "json" };
import { GlossaryEntrySchema } from "./schema.js";

describe("manual seed entries", () => {
  it("validates 58 curated public entries with disambiguation cases", () => {
    const entries = GlossaryEntrySchema.array().parse(manualSeeds.entries);
    const ids = new Set(entries.map((entry) => entry.id));
    const expansionsByTerm = new Map<string, Set<string>>();

    for (const entry of entries) {
      const expansions = expansionsByTerm.get(entry.term_normalized) ?? new Set<string>();
      for (const expansion of entry.expansions) {
        expansions.add(expansion);
      }
      expansionsByTerm.set(entry.term_normalized, expansions);
    }

    const overloadedTerms = [...expansionsByTerm.values()].filter(
      (expansions) => expansions.size > 1
    );

    expect(entries).toHaveLength(58);
    expect(ids.size).toBe(58);
    expect(entries.every((entry) => entry.layer === "public")).toBe(true);
    expect(entries.every((entry) => entry.sources.length > 0)).toBe(true);
    expect(entries.every((entry) => entry.examples.length > 0)).toBe(true);
    expect(entries.every((entry) => Array.isArray(entry.contemporaries))).toBe(true);
    expect(overloadedTerms.length).toBeGreaterThanOrEqual(3);
  });
});
