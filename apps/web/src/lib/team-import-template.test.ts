import { describe, expect, it } from "vitest";

import {
  parseTeamImportCsv,
  teamImportCsvTemplate,
  teamImportJsonTemplate
} from "./team-import-template";
import { validateTeamEntry } from "./team-entries";

describe("team import templates", () => {
  it("emits a valid JSON template", () => {
    const parsed = JSON.parse(teamImportJsonTemplate()) as { entries: unknown[] };

    expect(parsed.entries).toHaveLength(1);
    expect(validateTeamEntry(parsed.entries[0] as never)).toEqual([]);
  });

  it("parses the CSV template into importable entries", () => {
    const entries = parseTeamImportCsv(teamImportCsvTemplate());

    expect(entries).toHaveLength(1);
    expect(validateTeamEntry(entries![0]!)).toEqual([]);
    expect(entries![0]?.sources[0]?.license).toBe("proprietary-team");
  });

  it("parses quoted commas and quotes in CSV fields", () => {
    const csv = teamImportCsvTemplate().replace(
      '"Maximum acceptable time to restore a service after an incident."',
      '"Maximum acceptable time, also called ""restore target""."'
    );

    expect(parseTeamImportCsv(csv)?.[0]?.meaning).toBe(
      'Maximum acceptable time, also called "restore target".'
    );
  });
});
