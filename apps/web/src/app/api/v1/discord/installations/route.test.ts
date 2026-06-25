import { afterEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { resetApiKeysForTest, seedApiKeyForTest } from "@/lib/api-keys";
import { resetDiscordMetricsForTest } from "@/lib/discord-monitoring";

import { deleteDiscordInstallation, postDiscordInstallation } from "./handler";

function request(body: unknown, headers: Record<string, string> = {}): NextRequest {
  return new NextRequest("https://wat.example.com/api/v1/discord/installations", {
    body: JSON.stringify(body),
    headers: {
      authorization: "Bearer test-key",
      "content-type": "application/json",
      "x-wat-team-id": "team_123",
      "x-wat-user-id": "discord:installer",
      ...headers
    },
    method: "POST"
  });
}

const validInstall = {
  admin_role_ids: ["role_admin"],
  application_id: "discord-app-id",
  bot_user_id: "bot-user-id",
  discord_guild_id: "guild_123",
  guild_name: "Example Guild"
};

describe("Discord installations API", () => {
  afterEach(() => {
    resetDiscordMetricsForTest();
    resetApiKeysForTest();
  });

  it("upserts a Discord guild mapping", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });
    const response = await postDiscordInstallation(request(validInstall), {
      upsertInstall: async (input) => ({
        admin_role_ids: input.adminRoleIds ?? [],
        application_id: input.applicationId,
        bot_user_id: input.botUserId ?? null,
        discord_guild_id: input.discordGuildId,
        guild_name: input.guildName ?? null,
        id: "discord-install-guild_123",
        installed_at: "2026-06-25T00:00:00.000Z",
        installer_discord_user_id: input.installerDiscordUserId ?? null,
        team_id: input.teamId,
        updated_at: "2026-06-25T00:00:00.000Z"
      })
    });

    const body = (await response.json()) as { install?: { admin_role_ids?: string[] } };
    expect(response.status).toBe(201);
    expect(body.install?.admin_role_ids).toEqual(["role_admin"]);
  });

  it("requires API and team scope", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });

    expect(
      (await postDiscordInstallation(request(validInstall, { authorization: "Bearer bad-key" })))
        .status
    ).toBe(401);
    expect(
      (await postDiscordInstallation(request(validInstall, { "x-wat-team-id": "team_999" }))).status
    ).toBe(403);
  });

  it("rejects invalid installs", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });

    const response = await postDiscordInstallation(
      request({ ...validInstall, discord_guild_id: "" })
    );

    expect(response.status).toBe(400);
  });

  it("deletes a Discord guild mapping", async () => {
    seedApiKeyForTest({ key: "test-key", teamId: "team_123" });
    const response = await deleteDiscordInstallation(
      new NextRequest("https://wat.example.com/api/v1/discord/installations?guild_id=guild_123", {
        headers: {
          authorization: "Bearer test-key",
          "x-wat-team-id": "team_123"
        },
        method: "DELETE"
      }),
      {
        deleteInstall: async (discordGuildId, teamId) =>
          discordGuildId === "guild_123" && teamId === "team_123"
      }
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ deleted: true });
  });
});
