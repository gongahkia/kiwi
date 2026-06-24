import { describe, expect, it } from "vitest";

import { teamImportCsvTemplate, teamImportJsonTemplate } from "./team-import-template";
import { previewTeamImport } from "./team-import-preview";

describe("team import preview", () => {
  it("accepts valid JSON entries", () => {
    const preview = previewTeamImport(teamImportJsonTemplate(), "json");

    expect(preview.total).toBe(1);
    expect(preview.issues).toEqual([]);
    expect(preview.accepted[0]?.id).toBe("team-template-rto");
  });

  it("reports invalid JSON rows without blocking valid rows", () => {
    const payload = JSON.parse(teamImportJsonTemplate()) as {
      entries: Array<Record<string, unknown>>;
    };
    payload.entries.push({
      domains: [],
      expansion: "",
      id: "bad-entry",
      meaning: "",
      sources: [],
      term: ""
    });

    const preview = previewTeamImport(JSON.stringify(payload), "json");

    expect(preview.total).toBe(2);
    expect(preview.accepted).toHaveLength(1);
    expect(preview.issues).toEqual([
      {
        entryId: "bad-entry",
        message:
          "term is required; expansion is required; meaning is required; at least one domain is required; at least one source is required"
      }
    ]);
  });

  it("accepts CSV template rows", () => {
    const preview = previewTeamImport(teamImportCsvTemplate(), "csv");

    expect(preview.total).toBe(1);
    expect(preview.issues).toEqual([]);
    expect(preview.accepted[0]?.sources[0]?.license).toBe("proprietary-team");
  });

  it("reports malformed CSV", () => {
    const preview = previewTeamImport("id,term\nunterminated", "csv");

    expect(preview.accepted).toEqual([]);
    expect(preview.issues).toEqual([{ entryId: "file", message: "invalid csv import shape" }]);
  });
});
