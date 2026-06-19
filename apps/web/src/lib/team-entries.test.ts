import { describe, expect, it } from "vitest";

import {
  getTeamEntries,
  createTeamEntry,
  deleteTeamEntry,
  importTeamEntries,
  initialTeamEntries,
  resetTeamEntriesForTest,
  teamEntriesCsv,
  updateTeamEntry,
  type TeamEntry
} from "./team-entries";

describe("team export helpers", () => {
  it("exports every team entry source in CSV", () => {
    const csv = teamEntriesCsv();

    expect(csv).toContain("team-example-cap");
    expect(csv).toContain("team-example-df");
    for (const entry of initialTeamEntries) {
      for (const source of entry.sources) {
        expect(csv).toContain(source.url);
      }
    }
  });

  it("imports valid new entries and dedups existing entries", () => {
    resetTeamEntriesForTest();
    const imported: TeamEntry = {
      domains: ["reliability"],
      expansion: "Service Level Indicator",
      id: "team-example-sli",
      meaning: "Internal reliability metric.",
      sources: [
        {
          license: "MIT",
          publisher: "wat dev fixture",
          retrieved_at: "2026-06-19T00:00:00.000Z",
          snippet: "SLI is used by the reliability team.",
          title: "example.com reliability glossary fixture",
          url: "https://example.com/glossary/sli"
        }
      ],
      term: "SLI"
    };
    const result = importTeamEntries([initialTeamEntries[0] as TeamEntry, imported]);

    expect(result.inserted).toEqual([imported]);
    expect(result.skipped).toEqual([initialTeamEntries[0]]);
    expect(getTeamEntries()).toHaveLength(initialTeamEntries.length + 1);
    resetTeamEntriesForTest();
  });

  it("creates, edits, and deletes team entries", () => {
    resetTeamEntriesForTest();
    const entry: TeamEntry = {
      domains: ["security"],
      expansion: "Customer Access Policy",
      id: "team-example-cap-policy",
      meaning: "Policy for customer access reviews.",
      sources: [
        {
          license: "MIT",
          publisher: "wat dev fixture",
          retrieved_at: "2026-06-19T00:00:00.000Z",
          snippet: "CAP policy is reviewed quarterly.",
          title: "example.com access glossary fixture",
          url: "https://example.com/glossary/cap-policy"
        }
      ],
      term: "CAP"
    };

    expect(createTeamEntry(entry)).toEqual(entry);
    expect(updateTeamEntry(entry.id, { meaning: "Updated access policy." })).toMatchObject({
      meaning: "Updated access policy."
    });
    expect(deleteTeamEntry(entry.id)).toMatchObject({ id: entry.id });
    expect(getTeamEntries().map((item) => item.id)).not.toContain(entry.id);
    resetTeamEntriesForTest();
  });
});
