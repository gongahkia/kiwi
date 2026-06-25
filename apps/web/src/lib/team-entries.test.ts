import { describe, expect, it } from "vitest";

import { parseTeamImportCsv } from "./team-import-template";
import {
  createTeamEntry,
  deleteTeamEntry,
  getTeamEntries,
  importTeamEntries,
  initialTeamEntries,
  replaceTeamEntriesForTest,
  resetTeamEntriesForTest,
  teamEntriesCsv,
  updateTeamEntry,
  type TeamEntry
} from "./team-entries";

describe("team export helpers", () => {
  it("exports every team entry source in CSV", async () => {
    resetTeamEntriesForTest();
    const csv = teamEntriesCsv(await getTeamEntries());

    expect(csv).toContain("team-example-cap");
    expect(csv).toContain("team-example-df");
    for (const entry of initialTeamEntries) {
      for (const source of entry.sources) {
        expect(csv).toContain(source.url);
      }
    }
  });

  it("round-trips exported CSV and JSON into an empty team glossary", async () => {
    const csv = teamEntriesCsv(initialTeamEntries);
    const csvEntries = parseTeamImportCsv(csv)!;

    replaceTeamEntriesForTest([]);
    expect((await importTeamEntries("team_1", csvEntries)).inserted).toEqual(initialTeamEntries);
    expect(await getTeamEntries()).toEqual(initialTeamEntries);

    const json = JSON.stringify({ entries: initialTeamEntries });
    const jsonEntries = (JSON.parse(json) as { entries: TeamEntry[] }).entries;

    replaceTeamEntriesForTest([]);
    expect((await importTeamEntries("team_1", jsonEntries)).inserted).toEqual(initialTeamEntries);
    expect(await getTeamEntries()).toEqual(initialTeamEntries);
    resetTeamEntriesForTest();
  });

  it("imports valid new entries and dedups existing entries", async () => {
    resetTeamEntriesForTest();
    const imported: TeamEntry = {
      domains: ["reliability"],
      expansion: "Service Level Indicator",
      id: "team-example-sli",
      meaning: "Internal reliability metric.",
      sources: [
        {
          license: "proprietary-team",
          publisher: "wat dev fixture",
          retrieved_at: "2026-06-19T00:00:00.000Z",
          snippet: "SLI is used by the reliability team.",
          title: "example.com reliability glossary fixture",
          url: "https://example.com/glossary/sli"
        }
      ],
      term: "SLI"
    };
    const result = await importTeamEntries("team_1", [
      initialTeamEntries[0] as TeamEntry,
      imported
    ]);

    expect(result.inserted).toEqual([imported]);
    expect(result.skipped).toEqual([initialTeamEntries[0]]);
    expect(await getTeamEntries()).toHaveLength(initialTeamEntries.length + 1);
    resetTeamEntriesForTest();
  });

  it("validates custom entry source licenses", async () => {
    resetTeamEntriesForTest();
    const entry: TeamEntry = {
      domains: ["security"],
      expansion: "Generated Source",
      id: "team-generated-source",
      meaning: "Generated source fixture.",
      sources: [
        {
          license: "proprietary-team",
          publisher: "wat dev fixture",
          retrieved_at: "2026-06-19T00:00:00.000Z",
          snippet: "Generated private source.",
          title: "generated source",
          url: "https://wat.local/team/team-generated-source"
        }
      ],
      term: "GNS"
    };

    expect(await createTeamEntry("team_1", entry)).toEqual(entry);
    await expect(
      createTeamEntry("team_1", {
        ...entry,
        id: "team-generated-source-mit",
        sources: [{ ...entry.sources[0]!, license: "MIT" }],
        term: "GNM"
      })
    ).rejects.toThrow(/public-compatible source license requires an external source url/);
    expect(
      await createTeamEntry("team_1", {
        ...entry,
        id: "team-external-source-mit",
        sources: [{ ...entry.sources[0]!, license: "MIT", url: "https://example.com/source" }],
        term: "GNE"
      })
    ).toMatchObject({ id: "team-external-source-mit" });
    resetTeamEntriesForTest();
  });

  it("creates, edits, and deletes team entries", async () => {
    resetTeamEntriesForTest();
    const entry: TeamEntry = {
      domains: ["security"],
      expansion: "Customer Access Policy",
      id: "team-example-cap-policy",
      meaning: "Policy for customer access reviews.",
      sources: [
        {
          license: "proprietary-team",
          publisher: "wat dev fixture",
          retrieved_at: "2026-06-19T00:00:00.000Z",
          snippet: "CAP policy is reviewed quarterly.",
          title: "example.com access glossary fixture",
          url: "https://example.com/glossary/cap-policy"
        }
      ],
      term: "CAP"
    };

    expect(await createTeamEntry("team_1", entry)).toEqual(entry);
    expect(
      await updateTeamEntry("team_1", entry.id, { meaning: "Updated access policy." })
    ).toMatchObject({
      meaning: "Updated access policy."
    });
    expect(await deleteTeamEntry("team_1", entry.id)).toMatchObject({ id: entry.id });
    expect((await getTeamEntries()).map((item) => item.id)).not.toContain(entry.id);
    resetTeamEntriesForTest();
  });
});
