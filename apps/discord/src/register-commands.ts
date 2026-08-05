import {
  DISCORD_API_VERSION,
  discordCommandPayloads,
  discordCommandsJson
} from "./discord-commands.js";
import { defaultDiscordMonitor, type DiscordMonitor } from "./discord-monitoring.js";

export interface DiscordCommandRegistrationConfig {
  applicationId?: string;
  botToken?: string;
  guildId?: string;
}

export interface DiscordCommandRegistrationResult {
  commandCount: number;
  scope: "global" | "guild";
  status: number;
}

export function registrationConfigFromEnv(
  env: NodeJS.ProcessEnv = process.env
): DiscordCommandRegistrationConfig {
  return {
    applicationId: env.DISCORD_APPLICATION_ID,
    botToken: env.DISCORD_BOT_TOKEN,
    guildId: env.DISCORD_GUILD_ID
  };
}

export function discordCommandRegistrationUrl(config: DiscordCommandRegistrationConfig): URL {
  if (!config.applicationId) throw new Error("DISCORD_APPLICATION_ID is required");
  const base = `https://discord.com/api/v${DISCORD_API_VERSION}/applications/${encodeURIComponent(
    config.applicationId
  )}`;
  return new URL(
    config.guildId
      ? `${base}/guilds/${encodeURIComponent(config.guildId)}/commands`
      : `${base}/commands`
  );
}

export async function registerDiscordCommands(
  config: DiscordCommandRegistrationConfig = registrationConfigFromEnv(),
  client: typeof fetch = fetch,
  monitor: DiscordMonitor = defaultDiscordMonitor()
): Promise<DiscordCommandRegistrationResult> {
  if (!config.botToken) throw new Error("DISCORD_BOT_TOKEN is required");
  const url = discordCommandRegistrationUrl(config);
  const response = await client(url, {
    body: JSON.stringify(discordCommandPayloads),
    headers: {
      authorization: `Bot ${config.botToken}`,
      "content-type": "application/json"
    },
    method: "PUT"
  });
  monitor.increment("discord_register_commands_total", {
    scope: config.guildId ? "guild" : "global",
    status: response.status
  });
  if (!response.ok) throw new Error(`Discord command registration failed: ${response.status}`);
  return {
    commandCount: discordCommandPayloads.length,
    scope: config.guildId ? "guild" : "global",
    status: response.status
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  if (process.argv.includes("--dry-run")) {
    process.stdout.write(discordCommandsJson());
  } else {
    await registerDiscordCommands();
  }
}
