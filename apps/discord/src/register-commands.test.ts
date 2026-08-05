import { describe, expect, it } from "vitest";

import { discordCommandPayloads } from "./discord-commands.js";
import { discordCommandRegistrationUrl, registerDiscordCommands } from "./register-commands.js";

describe("Discord command registration", () => {
  it("declares lookup, write, and message commands", () => {
    expect(discordCommandPayloads.map((command) => command.name)).toEqual([
      "wat",
      "wat-alt",
      "wat-suggest",
      "wat-define",
      "Explain acronyms"
    ]);
    expect(discordCommandPayloads.find((command) => command.name === "wat-define")).toMatchObject({
      default_member_permissions: "8"
    });
  });

  it("builds guild and global registration URLs", () => {
    expect(discordCommandRegistrationUrl({ applicationId: "app_123" }).toString()).toBe(
      "https://discord.com/api/v10/applications/app_123/commands"
    );
    expect(
      discordCommandRegistrationUrl({ applicationId: "app_123", guildId: "guild_123" }).toString()
    ).toBe("https://discord.com/api/v10/applications/app_123/guilds/guild_123/commands");
  });

  it("bulk overwrites commands with bot auth", async () => {
    const calls: Array<{ body: unknown; headers: Record<string, string>; url: string }> = [];
    const client: typeof fetch = async (input, init) => {
      calls.push({
        body: JSON.parse(String(init?.body)),
        headers: Object.fromEntries(new Headers(init?.headers).entries()),
        url: String(input)
      });
      return Response.json([], { status: 200 });
    };

    const result = await registerDiscordCommands(
      {
        applicationId: "app_123",
        botToken: "bot-token",
        guildId: "guild_123"
      },
      client
    );

    expect(result).toEqual({ commandCount: 5, scope: "guild", status: 200 });
    expect(calls[0]?.headers.authorization).toBe("Bot bot-token");
    expect(calls[0]?.body).toEqual(discordCommandPayloads);
  });
});
