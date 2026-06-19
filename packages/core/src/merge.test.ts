import { describe, expect, it } from "vitest";

import { mergeLayeredEntry } from "./merge.js";
import type { EntryLayer, GlossaryEntry } from "./schema.js";

function entry(layer: EntryLayer, id = layer): GlossaryEntry {
  return {
    aliases: [],
    coiner: null,
    confidence_tier: layer === "public" ? "T2" : "T4",
    created_at: "2026-01-01T00:00:00.000Z",
    deprecated: false,
    deprecated_reason: null,
    domains: ["platform"],
    examples: [`${layer} example`],
    expansions: [`${layer} expansion`],
    id,
    layer,
    license: "MIT",
    meaning_long: `${layer} long meaning`,
    meaning_short: `${layer} short meaning`,
    related_terms: [],
    sources: [
      {
        license: "MIT",
        publisher: `${layer} publisher`,
        retrieved_at: "2026-01-01T00:00:00.000Z",
        snippet: `${layer} snippet`,
        source_quality: layer === "public" ? "canonical" : "community",
        title: `${layer} title`,
        url: `https://example.com/${layer}`
      }
    ],
    team_id: layer === "team" ? "team_1" : null,
    term: "SLA",
    term_normalized: "sla",
    updated_at: "2026-01-01T00:00:00.000Z",
    year_coined: null
  };
}

describe("mergeLayeredEntry", () => {
  it("returns null with no layers", () => {
    expect(mergeLayeredEntry({})).toBeNull();
  });

  it("returns public when only public exists", () => {
    expect(mergeLayeredEntry({ public: entry("public") })?.winningLayer).toBe("public");
  });

  it("returns team over public", () => {
    expect(mergeLayeredEntry({ public: entry("public"), team: entry("team") })?.entry.layer).toBe(
      "team"
    );
  });

  it("returns personal over team and public", () => {
    const merged = mergeLayeredEntry({
      personal: entry("personal"),
      public: entry("public"),
      team: entry("team")
    });

    expect(merged?.entry.layer).toBe("personal");
  });

  it("returns personal over public when team is absent", () => {
    expect(
      mergeLayeredEntry({ personal: entry("personal"), public: entry("public") })?.entry.layer
    ).toBe("personal");
  });

  it("returns team when only team exists", () => {
    expect(mergeLayeredEntry({ team: entry("team") })?.entry.layer).toBe("team");
  });

  it("returns personal when only personal exists", () => {
    expect(mergeLayeredEntry({ personal: entry("personal") })?.entry.layer).toBe("personal");
  });

  it("preserves provenance for every present layer", () => {
    const merged = mergeLayeredEntry({
      personal: entry("personal"),
      public: entry("public"),
      team: entry("team")
    });

    expect(merged?.provenance.map((item) => item.layer)).toEqual(["public", "team", "personal"]);
  });

  it("preserves source provenance", () => {
    const merged = mergeLayeredEntry({ public: entry("public"), team: entry("team") });

    expect(merged?.provenance.map((item) => item.sources[0]?.url)).toEqual([
      "https://example.com/public",
      "https://example.com/team"
    ]);
  });

  it("reports overridden layers", () => {
    const merged = mergeLayeredEntry({
      personal: entry("personal"),
      public: entry("public"),
      team: entry("team")
    });

    expect(merged?.overriddenLayers).toEqual(["public", "team"]);
  });

  it("returns a cloned selected entry", () => {
    const publicEntry = entry("public");
    const merged = mergeLayeredEntry({ public: publicEntry });

    expect(merged?.entry).toEqual(publicEntry);
    expect(merged?.entry).not.toBe(publicEntry);
  });
});
