import { NextRequest } from "next/server";
import { afterEach, describe, expect, it } from "vitest";

import { recordAuditLog, resetAuditLogForTest } from "@/lib/audit-log";
import { testSessionToken } from "@/lib/session";
import { GET } from "./route";

describe("GET /team/admin/audit/api", () => {
  afterEach(resetAuditLogForTest);

  it("paginates audit entries", async () => {
    await recordAuditLog({
      action: "create",
      actor_id: "admin",
      after_jsonb: { id: "one" },
      before_jsonb: null,
      target_id: "one",
      target_type: "entry",
      team_id: "team_1"
    });
    await recordAuditLog({
      action: "update",
      actor_id: "admin",
      after_jsonb: { id: "two" },
      before_jsonb: { id: "two" },
      target_id: "two",
      target_type: "entry",
      team_id: "team_1"
    });

    const response = await GET(
      new NextRequest("https://wat.example.com/team/admin/audit/api?limit=1", {
        headers: { cookie: `next-auth.session-token=${testSessionToken()}` }
      })
    );
    const body = (await response.json()) as {
      audit: unknown[];
      page: { limit: number; next_cursor: string | null; total: number };
    };

    expect(body.audit).toHaveLength(1);
    expect(body.page).toMatchObject({ limit: 1, next_cursor: "1", total: 2 });
  });
});
