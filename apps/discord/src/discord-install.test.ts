import { describe, expect, it } from "vitest";

import { buildDiscordInstallUrl, parseDiscordInstallScopes } from "./discord-install.js";

describe("Discord install URL", () => {
  it("builds an applications.commands install URL by default", () => {
    const url = buildDiscordInstallUrl({
      applicationId: "app_123",
      guildId: "guild_123",
      integrationType: "0"
    });

    expect(url.origin).toBe("https://discord.com");
    expect(url.pathname).toBe("/oauth2/authorize");
    expect(url.searchParams.get("client_id")).toBe("app_123");
    expect(url.searchParams.get("scope")).toBe("applications.commands");
    expect(url.searchParams.get("guild_id")).toBe("guild_123");
    expect(url.searchParams.get("integration_type")).toBe("0");
  });

  it("adds bot permissions only when bot scope is requested", () => {
    const commandsOnly = buildDiscordInstallUrl({
      applicationId: "app_123",
      permissions: "2048"
    });
    const bot = buildDiscordInstallUrl({
      applicationId: "app_123",
      permissions: "2048",
      scopes: ["applications.commands", "bot"]
    });

    expect(commandsOnly.searchParams.get("permissions")).toBeNull();
    expect(bot.searchParams.get("permissions")).toBe("2048");
  });

  it("parses comma and space separated scopes", () => {
    expect(parseDiscordInstallScopes("applications.commands, bot applications.commands")).toEqual([
      "applications.commands",
      "bot"
    ]);
  });
});
