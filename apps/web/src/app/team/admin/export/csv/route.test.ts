import { NextRequest } from "next/server";
import { afterEach, describe, expect, it } from "vitest";

import { initialTeamEntries, resetTeamEntriesForTest } from "@/lib/team-entries";
import { GET } from "./route";

describe("GET /team/admin/export/csv", () => {
  afterEach(resetTeamEntriesForTest);

  it("paginates CSV exports with cursor headers", async () => {
    const response = GET(new NextRequest("https://wat.example.com/team/admin/export/csv?limit=1"));
    const csv = await response.text();

    expect(csv).toContain("team-example-cap");
    expect(csv).not.toContain("team-example-df");
    expect(response.headers.get("x-page-limit")).toBe("1");
    expect(response.headers.get("x-page-total")).toBe(String(initialTeamEntries.length));
    expect(response.headers.get("x-next-cursor")).toBe("1");
  });
});
