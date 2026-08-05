import { mkdtemp } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { describe, expect, it } from "vitest";

import { encryptToken } from "./token-encryption.js";
import {
  JsonFileSlackInstallStore,
  MemorySlackInstallStore,
  PgSlackInstallStore
} from "./slack-install-store.js";

const record = {
  appId: "A_WAT",
  botScopes: ["commands"],
  botToken: encryptToken("xoxb-token", "enc-key"),
  botUserId: "U_BOT",
  installedAt: "2026-06-25T00:00:00.000Z",
  installerSlackUserId: "U_INSTALLER",
  slackTeamId: "T_WAT",
  slackTeamName: "Wat Workspace",
  updatedAt: "2026-06-25T00:00:00.000Z",
  userScopes: ["identity.basic"],
  watTeamId: "team_wat"
};

describe("Slack install stores", () => {
  it("stores installs in memory without exposing mutable state", async () => {
    const store = new MemorySlackInstallStore();

    await store.upsert(record);
    const stored = await store.getBySlackTeamId("T_WAT");
    stored!.botScopes.push("chat:write");

    expect((await store.getBySlackTeamId("T_WAT"))?.botScopes).toEqual(["commands"]);

    await store.deleteBySlackTeamId("T_WAT");
    expect(await store.getBySlackTeamId("T_WAT")).toBeNull();
  });

  it("persists installs to JSON", async () => {
    const dir = await mkdtemp(join(tmpdir(), "wat-slack-install-store-"));
    const path = join(dir, "installs.json");
    const store = new JsonFileSlackInstallStore(path);

    await store.upsert(record);

    const restored = await new JsonFileSlackInstallStore(path).getBySlackTeamId("T_WAT");
    expect(restored).toMatchObject({
      appId: "A_WAT",
      botScopes: ["commands"],
      slackTeamId: "T_WAT",
      watTeamId: "team_wat"
    });
    expect(restored?.botToken.ciphertext).not.toContain("xoxb-token");

    await store.deleteBySlackTeamId("T_WAT");
    expect(await new JsonFileSlackInstallStore(path).getBySlackTeamId("T_WAT")).toBeNull();
  });

  it("upserts and reads installs through Postgres", async () => {
    const queries: Array<{ sql: string; values?: unknown[] }> = [];
    const client = {
      async query<Row>(sql: string, values?: unknown[]) {
        queries.push({ sql, values });
        if (sql.includes("select")) {
          return {
            rows: [
              {
                app_id: "A_WAT",
                bot_scopes: ["commands"],
                bot_token_encrypted: record.botToken,
                bot_user_id: "U_BOT",
                enterprise_id: null,
                enterprise_name: null,
                installed_at: new Date("2026-06-25T00:00:00.000Z"),
                installer_slack_user_id: "U_INSTALLER",
                slack_team_id: "T_WAT",
                slack_team_name: "Wat Workspace",
                team_id: "team_wat",
                updated_at: new Date("2026-06-25T00:00:00.000Z"),
                user_scopes: ["identity.basic"],
                user_token_encrypted: null
              } as Row
            ]
          };
        }
        return { rows: [] };
      }
    };
    const store = new PgSlackInstallStore(client);

    await store.upsert(record);
    const restored = await store.getBySlackTeamId("T_WAT");
    const upsertAudit = queries.find((query) => query.sql.includes("insert into audit_log"));

    expect(queries[0]?.sql).toContain("insert into slack_installs");
    expect(queries[0]?.values?.[0]).toBe("slack-install-t_wat");
    expect(upsertAudit?.values?.[2]).toBe("slack_install.upsert");
    expect(JSON.stringify(upsertAudit?.values)).not.toContain(record.botToken.ciphertext);
    expect(restored).toMatchObject({
      botScopes: ["commands"],
      slackTeamId: "T_WAT",
      watTeamId: "team_wat"
    });

    await store.deleteBySlackTeamId("T_WAT");
    const deleteAudit = queries
      .filter((query) => query.sql.includes("insert into audit_log"))
      .at(-1);
    expect(queries.some((query) => query.sql.includes("delete from slack_installs"))).toBe(true);
    expect(deleteAudit?.values?.[2]).toBe("slack_install.delete");
  });
});
