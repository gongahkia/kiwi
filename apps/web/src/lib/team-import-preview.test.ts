import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { teamImportCsvTemplate, teamImportJsonTemplate } from "./team-import-template";
import { previewTeamImport } from "./team-import-preview";
import type { TeamEntry } from "./team-entries";

describe("team import preview", () => {
  it("accepts valid JSON entries", () => {
    const preview = previewTeamImport(teamImportJsonTemplate(), "json");

    expect(preview.total).toBe(1);
    expect(preview.conflicts).toEqual([]);
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

  it("marks id and term/expansion conflicts against existing entries", () => {
    const existing = previewTeamImport(teamImportJsonTemplate(), "json").accepted[0] as TeamEntry;
    const byId = { ...existing, expansion: "Recovery Time Goal" };
    const byKey = { ...existing, id: "team-template-rto-v2" };
    const payload = JSON.stringify({ entries: [byId, byKey] });

    const preview = previewTeamImport(payload, "json", [existing]);

    expect(preview.conflicts).toEqual([
      {
        entryId: "team-template-rto",
        existingId: "team-template-rto",
        reason: "id"
      },
      {
        entryId: "team-template-rto-v2",
        existingId: "team-template-rto",
        reason: "term_expansion"
      }
    ]);
  });

  it("reports malformed CSV", () => {
    const preview = previewTeamImport("id,term\nunterminated", "csv");

    expect(preview.accepted).toEqual([]);
    expect(preview.issues).toEqual([{ entryId: "file", message: "invalid csv import shape" }]);
  });

  it("wires create, update, and skip choices into the import panel", () => {
    const source = readFileSync(
      join(process.cwd(), "src/components/team-import-panel.tsx"),
      "utf8"
    );

    expect(source).toContain("Create");
    expect(source).toContain("Update");
    expect(source).toContain("Skip");
    expect(source).toContain("/team/admin/import/api");
    expect(source).toContain("/team/admin/entries/api");
  });
});
