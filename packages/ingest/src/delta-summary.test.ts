import { describe, expect, it } from "vitest";

import {
  assertNoSourceLicenseChanges,
  renderDeltaSummary,
  summarizeDelta,
  type DeltaFile
} from "./delta-summary.js";

const baseEntry = {
  aliases: [],
  dedup_key: "api:application programming interface",
  contemporaries: [],
  domains: ["web"],
  examples: [],
  expansion_normalized: "application programming interface",
  expansions: ["Application Programming Interface"],
  meaning_short: "Interface for software systems.",
  sources: [
    {
      license: "MIT",
      publisher: "Example",
      retrieved_at: "2026-06-18T00:00:00.000Z",
      snippet: "API fixture.",
      source_quality: "secondary" as const,
      title: "API",
      url: "https://example.com/api"
    }
  ],
  term: "API",
  term_normalized: "api"
};

describe("delta summary", () => {
  it("counts added changed and removed entries", () => {
    const previous: DeltaFile = {
      entries: [
        baseEntry,
        {
          ...baseEntry,
          dedup_key: "sdk:software development kit",
          expansion_normalized: "software development kit",
          expansions: ["Software Development Kit"],
          term: "SDK",
          term_normalized: "sdk"
        }
      ],
      generated_at: "2026-06-18T00:00:00.000Z",
      source: "example"
    };
    const current: DeltaFile = {
      entries: [
        { ...baseEntry, meaning_short: "Changed meaning." },
        {
          ...baseEntry,
          dedup_key: "cli:command line interface",
          expansion_normalized: "command line interface",
          expansions: ["Command Line Interface"],
          term: "CLI",
          term_normalized: "cli"
        }
      ],
      generated_at: "2026-06-19T00:00:00.000Z",
      source: "example"
    };
    const summary = summarizeDelta(current, previous);

    expect(summary.added).toHaveLength(1);
    expect(summary.changed).toHaveLength(1);
    expect(summary.license_changes).toHaveLength(0);
    expect(summary.quality_samples).toHaveLength(2);
    expect(summary.removed).toHaveLength(1);
    const rendered = renderDeltaSummary(summary, "data/deltas/2026-06-19/example.json");

    expect(rendered).toContain("| Added | 1 |");
    expect(rendered).toContain("## Quality review sample");
    expect(rendered).toContain("Review these deterministic-random entries");
  });

  it("blocks source license metadata changes until reviewed", () => {
    const previous: DeltaFile = {
      entries: [baseEntry],
      generated_at: "2026-06-18T00:00:00.000Z",
      source: "example"
    };
    const current: DeltaFile = {
      entries: [
        {
          ...baseEntry,
          sources: [{ ...baseEntry.sources[0]!, license: "CC-BY-4.0" }]
        }
      ],
      generated_at: "2026-06-19T00:00:00.000Z",
      source: "example"
    };
    const summary = summarizeDelta(current, previous);

    expect(summary.license_changes).toEqual([
      {
        current_entry: "api:application programming interface",
        current_license: "CC-BY-4.0",
        previous_entry: "api:application programming interface",
        previous_license: "MIT",
        title: "API",
        url: "https://example.com/api"
      }
    ]);
    expect(renderDeltaSummary(summary, "data/deltas/2026-06-19/example.json")).toContain(
      "Automatic import is blocked"
    );
    expect(() => assertNoSourceLicenseChanges(summary)).toThrow(/source license change/);
  });
});
