import { NextRequest } from "next/server";
import { afterEach, describe, expect, it } from "vitest";

import { testSessionToken } from "@/lib/session";
import { initialTeamEntries, resetTeamEntriesForTest } from "@/lib/team-entries";
import { GET } from "./route";

describe("GET /team/admin/export/json", () => {
  afterEach(resetTeamEntriesForTest);

  it("paginates JSON exports", async () => {
    const response = await GET(
      new NextRequest("https://wat.example.com/team/admin/export/json?limit=1", {
        headers: { cookie: `next-auth.session-token=${testSessionToken()}` }
      })
    );
    const body = (await response.json()) as {
      entries: unknown[];
      page: { limit: number; next_cursor: string | null; total: number };
    };

    expect(body.entries).toHaveLength(1);
    expect(body.page).toMatchObject({
      limit: 1,
      next_cursor: "1",
      total: initialTeamEntries.length
    });
  });
});
