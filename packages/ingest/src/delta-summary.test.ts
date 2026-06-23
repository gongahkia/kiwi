import { describe, expect, it } from "vitest";

import { renderDeltaSummary, summarizeDelta, type DeltaFile } from "./delta-summary.js";

const baseEntry = {
  dedup_key: "api:application programming interface",
  contemporaries: [],
  domains: ["web"],
  examples: [],
  expansion_normalized: "application programming interface",
  expansions: ["Application Programming Interface"],
  meaning_short: "Interface for software systems.",
  sources: [],
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
    expect(summary.removed).toHaveLength(1);
    expect(renderDeltaSummary(summary, "data/deltas/2026-06-19/example.json")).toContain(
      "| Added | 1 |"
    );
  });
});
