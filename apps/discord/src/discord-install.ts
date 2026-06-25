export interface DiscordInstallUrlConfig {
  applicationId?: string;
  disableGuildSelect?: boolean;
  guildId?: string;
  integrationType?: "0" | "1";
  permissions?: string;
  scopes?: string[];
}

export function buildDiscordInstallUrl(config: DiscordInstallUrlConfig): URL {
  if (!config.applicationId) throw new Error("DISCORD_APPLICATION_ID is required");
  const url = new URL("https://discord.com/oauth2/authorize");
  url.searchParams.set("client_id", config.applicationId);
  url.searchParams.set(
    "scope",
    (config.scopes?.length ? config.scopes : ["applications.commands"]).join(" ")
  );
  if (config.guildId) url.searchParams.set("guild_id", config.guildId);
  if (config.disableGuildSelect) url.searchParams.set("disable_guild_select", "true");
  if (config.integrationType) url.searchParams.set("integration_type", config.integrationType);
  if (config.permissions && config.scopes?.includes("bot")) {
    url.searchParams.set("permissions", config.permissions);
  }
  return url;
}

export function parseDiscordInstallScopes(value: string | undefined): string[] {
  const scopes = value
    ?.split(/[,\s]+/)
    .map((scope) => scope.trim())
    .filter(Boolean);
  return scopes && scopes.length > 0 ? Array.from(new Set(scopes)) : ["applications.commands"];
}
