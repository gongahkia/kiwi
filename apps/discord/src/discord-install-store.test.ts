import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  JsonFileDiscordInstallStore,
  MemoryDiscordInstallStore,
  PgDiscordInstallStore
} from "./discord-install-store.js";

const record = {
  adminRoleIds: ["R_ADMIN"],
  appId: "A_WAT",
  botUserId: "U_BOT",
  discordGuildId: "G_WAT",
  guildName: "Wat Guild",
  installedAt: "2026-06-25T00:00:00.000Z",
  installerDiscordUserId: "U_INSTALLER",
  updatedAt: "2026-06-25T00:00:00.000Z",
  watTeamId: "team_wat"
};

describe("Discord install stores", () => {
  it("stores installs in memory without exposing mutable state", async () => {
    const store = new MemoryDiscordInstallStore();

    await store.upsert(record);
    const stored = await store.getByGuildId("G_WAT");
    stored!.adminRoleIds.push("R_OWNER");

    expect((await store.getByGuildId("G_WAT"))?.adminRoleIds).toEqual(["R_ADMIN"]);

    await store.deleteByGuildId("G_WAT");
    expect(await store.getByGuildId("G_WAT")).toBeNull();
  });

  it("persists installs to JSON", async () => {
    const dir = await mkdtemp(join(tmpdir(), "wat-discord-install-store-"));
    const path = join(dir, "installs.json");
    const store = new JsonFileDiscordInstallStore(path);

    await store.upsert(record);

    const restored = await new JsonFileDiscordInstallStore(path).getByGuildId("G_WAT");
    expect(restored).toMatchObject({
      adminRoleIds: ["R_ADMIN"],
      discordGuildId: "G_WAT",
      watTeamId: "team_wat"
    });

    await store.deleteByGuildId("G_WAT");
    expect(await new JsonFileDiscordInstallStore(path).getByGuildId("G_WAT")).toBeNull();
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
                admin_role_ids: ["R_ADMIN"],
                application_id: "A_WAT",
                bot_user_id: "U_BOT",
                discord_guild_id: "G_WAT",
                guild_name: "Wat Guild",
                installed_at: new Date("2026-06-25T00:00:00.000Z"),
                installer_discord_user_id: "U_INSTALLER",
                team_id: "team_wat",
                updated_at: new Date("2026-06-25T00:00:00.000Z")
              } as Row
            ]
          };
        }
        return { rows: [] };
      }
    };
    const store = new PgDiscordInstallStore(client);

    await store.upsert(record);
    const restored = await store.getByGuildId("G_WAT");

    expect(queries[0]?.sql).toContain("insert into discord_installs");
    expect(queries[0]?.values?.[0]).toBe("discord-install-g_wat");
    expect(restored).toMatchObject({
      adminRoleIds: ["R_ADMIN"],
      discordGuildId: "G_WAT",
      watTeamId: "team_wat"
    });

    await store.deleteByGuildId("G_WAT");
    expect(queries.at(-1)?.sql).toContain("delete from discord_installs");
  });
});
