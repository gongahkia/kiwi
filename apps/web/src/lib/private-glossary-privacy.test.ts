import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { createPersonalEntry, resetPersonalEntriesForTest } from "./personal-entries";
import { getScopedPersonalEntries, getScopedTeamEntries } from "./search-data";
import { sourceInventoryFromEntries } from "./source-inventory";
import {
  createTeamEntry,
  replaceTeamEntriesForTest,
  resetTeamEntriesForTest,
  type TeamEntry
} from "./team-entries";

function privateEntry(id: string, license: "proprietary-personal" | "proprietary-team"): TeamEntry {
  return {
    domains: ["private"],
    expansion: "Customer Access Policy",
    id,
    meaning: "Private customer access note.",
    sources: [
      {
        license,
        publisher: "wat private fixture",
        retrieved_at: "2026-06-24T00:00:00.000Z",
        snippet: "CAP is private glossary data.",
        title: "Private glossary fixture",
        url: `https://example.com/${id}`
      }
    ],
    term: "CAP"
  };
}

describe("private glossary privacy defaults", () => {
  afterEach(() => {
    resetPersonalEntriesForTest();
    resetTeamEntriesForTest();
    replaceTeamEntriesForTest([], "team_private");
  });

  it("keeps personal and team search entries out of public/open-source labels", async () => {
    resetPersonalEntriesForTest();
    replaceTeamEntriesForTest([]);
    replaceTeamEntriesForTest([], "team_private");

    await createPersonalEntry(
      "user_private",
      privateEntry("personal-private-cap", "proprietary-personal")
    );
    await createTeamEntry("team_private", privateEntry("team-private-cap", "proprietary-team"));

    const personal = (await getScopedPersonalEntries({ type: "api", userId: "user_private" }))[0];
    const team = (
      await getScopedTeamEntries({
        teamId: "team_private",
        type: "api",
        userId: "user_private"
      })
    )[0];

    expect(personal).toMatchObject({
      confidence_tier: "T4",
      layer: "personal",
      sources: [{ license: "proprietary-personal", source_quality: "community" }]
    });
    expect(team).toMatchObject({
      confidence_tier: "T4",
      layer: "team",
      sources: [{ license: "proprietary-team", source_quality: "community" }]
    });
    expect(sourceInventoryFromEntries([personal!, team!])).toEqual([]);
  });

  it("documents current private-data flows and labels", () => {
    const privacy = readFileSync(join(process.cwd(), "src/app/privacy/page.tsx"), "utf8");
    const terms = readFileSync(join(process.cwd(), "src/app/terms/page.tsx"), "utf8");

    expect(privacy).toContain("Team and personal entries are private layer data");
    expect(privacy).toContain("proprietary-team");
    expect(privacy).toContain("proprietary-personal");
    expect(privacy).toContain("Search sends q, limit, optional context");
    expect(privacy).toContain("Slack sends the explicit slash-command term");
    expect(privacy).toContain("MCP tools send term, domain, context");
    expect(terms).toContain("Team and personal entries remain scoped");
  });
});
