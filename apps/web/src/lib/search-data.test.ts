import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { createPersonalEntry, resetPersonalEntriesForTest } from "@/lib/personal-entries";
import type { WatSessionUser } from "@/lib/session";
import {
  replaceTeamEntriesForTest,
  resetTeamEntriesForTest,
  type TeamEntry
} from "@/lib/team-entries";
import { getVisibleEntriesForSession } from "./search-data";

function entry(id: string, term: string, expansion: string): TeamEntry {
  return {
    domains: ["platform"],
    expansion,
    id,
    meaning: `${term} test meaning.`,
    sources: [
      {
        license: "proprietary-team",
        publisher: "wat test",
        retrieved_at: "2026-06-24T00:00:00.000Z",
        snippet: `${term} fixture.`,
        title: `${term} fixture`,
        url: `https://example.com/${id}`
      }
    ],
    term
  };
}

const session: WatSessionUser = {
  email: "user_1@example.test",
  id: "user_1",
  role: "member",
  teamId: "team_1"
};

describe("getVisibleEntriesForSession", () => {
  beforeEach(async () => {
    resetPersonalEntriesForTest();
    replaceTeamEntriesForTest([entry("team-visible", "RTO", "Recovery Time Objective")]);
    replaceTeamEntriesForTest([entry("team-hidden", "HID", "Hidden Team Entry")], "team_2");
    await createPersonalEntry("user_1", entry("personal-visible", "CAP", "Change Approval"));
    await createPersonalEntry("user_2", entry("personal-hidden", "PHI", "Private Hidden"));
  });

  afterEach(() => {
    resetPersonalEntriesForTest();
    resetTeamEntriesForTest();
    replaceTeamEntriesForTest([], "team_2");
  });

  it("includes public, current-team, and current-user entries only", async () => {
    const entries = await getVisibleEntriesForSession(session);

    expect(entries).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: "team-visible", layer: "team" }),
        expect.objectContaining({ id: "personal-visible", layer: "personal" })
      ])
    );
    expect(entries.some((item) => item.layer === "public")).toBe(true);
    expect(entries.some((item) => item.id === "team-hidden")).toBe(false);
    expect(entries.some((item) => item.id === "personal-hidden")).toBe(false);
  });
});
