import { describe, expect, it } from "vitest";

import { recoverTeamAdmin } from "./recover-team-admin.js";

describe("recoverTeamAdmin", () => {
  it("promotes a member and writes audit when the team has no admins", async () => {
    const calls: Array<{ sql: string; values?: unknown[] }> = [];
    const client = {
      async query<Row>(sql: string, values?: unknown[]) {
        calls.push({ sql, values });
        if (sql.includes("count(*)")) return { rows: [{ count: "0" } as Row] };
        if (sql.startsWith("select id")) {
          return {
            rows: [
              {
                email: "owner@example.com",
                id: "user_1",
                role: "member",
                team_id: "team_1"
              } as Row
            ]
          };
        }
        if (sql.startsWith("update users")) {
          return {
            rows: [
              {
                email: "owner@example.com",
                id: "user_1",
                role: "admin",
                team_id: "team_1"
              } as Row
            ]
          };
        }
        return { rows: [] };
      }
    };

    await expect(
      recoverTeamAdmin(client, { teamId: "team_1", userEmail: "owner@example.com" })
    ).resolves.toMatchObject({ id: "user_1", role: "admin" });

    expect(calls.map((call) => call.sql.trim().split(/\s+/).slice(0, 3).join(" "))).toEqual([
      "begin",
      "select count(*)::text as",
      "select id, email,",
      "update users set",
      "insert into audit_log",
      "commit"
    ]);
    expect(calls.at(-2)?.values?.[2]).toBe("user_1");
  });

  it("fails closed when the team still has an admin", async () => {
    const calls: string[] = [];
    const client = {
      async query<Row>(sql: string) {
        calls.push(sql);
        if (sql.includes("count(*)")) return { rows: [{ count: "1" } as Row] };
        return { rows: [] };
      }
    };

    await expect(
      recoverTeamAdmin(client, { teamId: "team_1", userEmail: "owner@example.com" })
    ).rejects.toThrow("team already has an admin");
    expect(calls.at(-1)).toBe("rollback");
  });
});
