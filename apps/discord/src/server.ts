import { createPublicKey, verify as cryptoVerify } from "node:crypto";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";

import { buildDiscordInstallUrl, parseDiscordInstallScopes } from "./discord-install.js";
import {
  JsonFileDiscordInstallStore,
  MemoryDiscordInstallStore,
  PgDiscordInstallStore,
  type DiscordInstallRecord,
  type DiscordInstallStore
} from "./discord-install-store.js";
import { defaultDiscordMonitor, type DiscordMonitor } from "./discord-monitoring.js";

const ed25519PublicKeySpkiPrefix = Buffer.from("302a300506032b6570032100", "hex");

const DiscordInteractionType = {
  APPLICATION_COMMAND: 2,
  PING: 1
} as const;

const DiscordInteractionCallbackType = {
  CHANNEL_MESSAGE_WITH_SOURCE: 4,
  PONG: 1
} as const;

const DiscordMessageFlags = {
  EPHEMERAL: 64
} as const;

const administratorPermission = 8n;

export interface DiscordRuntimeConfig {
  applicationId?: string;
  botToken?: string;
  databaseUrl?: string;
  discordAdminRoleIds?: string[];
  discordAdminUserIds?: string[];
  discordGuildWatTeamMap?: Record<string, string>;
  installStore?: "json" | "memory" | "postgres";
  installStorePath?: string;
  installDisableGuildSelect?: boolean;
  installGuildId?: string;
  installIntegrationType?: "0" | "1";
  installPermissions?: string;
  installScopes?: string[];
  metricsToken?: string;
  port: number;
  publicKey?: string;
  watApiBaseUrl: string;
  watApiKey?: string;
  watTeamId?: string;
}

export interface DiscordRuntimeDeps {
  fetchLookup?: typeof fetch;
  fetchWrite?: typeof fetch;
  installStore?: DiscordInstallStore;
  monitor?: DiscordMonitor;
}

interface DiscordUser {
  id?: string;
  username?: string;
}

interface DiscordMember {
  permissions?: string;
  roles?: string[];
  user?: DiscordUser;
}

interface DiscordInteraction {
  application_id?: string;
  channel?: { id?: string; name?: string };
  channel_id?: string;
  data?: DiscordApplicationCommandData;
  guild_id?: string;
  id?: string;
  member?: DiscordMember;
  token?: string;
  type?: number;
  user?: DiscordUser;
}

interface DiscordApplicationCommandData {
  name?: string;
  options?: DiscordCommandOption[];
  resolved?: {
    messages?: Record<string, { content?: string }>;
  };
  target_id?: string;
  type?: number;
}

interface DiscordCommandOption {
  name?: string;
  value?: unknown;
}

interface SearchEntry {
  contemporaries?: string[];
  domains?: string[];
  expansions?: string[];
  id?: string;
  layer?: string;
  meaning_short?: string;
  term?: string;
}

interface SearchResponse {
  matches?: Array<{ entry?: SearchEntry }>;
}

interface InteractionResponse {
  data?: {
    allowed_mentions?: { parse: string[] };
    content: string;
    flags: number;
  };
  type: number;
}

interface ResolvedInstall {
  install: DiscordInstallRecord | null;
  watTeamId?: string;
}

export function configFromEnv(env: NodeJS.ProcessEnv = process.env): DiscordRuntimeConfig {
  return {
    applicationId: env.DISCORD_APPLICATION_ID,
    botToken: env.DISCORD_BOT_TOKEN,
    databaseUrl: env.DISCORD_DATABASE_URL ?? env.WAT_DATABASE_URL ?? env.DATABASE_URL,
    discordAdminRoleIds: csvEnv(env.DISCORD_ADMIN_ROLE_IDS),
    discordAdminUserIds: csvEnv(env.DISCORD_ADMIN_USER_IDS),
    discordGuildWatTeamMap: parseDiscordGuildWatTeamMap(env.WAT_DISCORD_GUILD_MAP),
    installStore: installStoreKind(env.DISCORD_INSTALL_STORE),
    installStorePath: env.DISCORD_INSTALL_STORE_PATH ?? ".wat-discord-installs.json",
    installDisableGuildSelect: env.DISCORD_INSTALL_DISABLE_GUILD_SELECT === "true",
    installGuildId: env.DISCORD_INSTALL_GUILD_ID,
    installIntegrationType:
      env.DISCORD_INSTALL_INTEGRATION_TYPE === "0" || env.DISCORD_INSTALL_INTEGRATION_TYPE === "1"
        ? env.DISCORD_INSTALL_INTEGRATION_TYPE
        : "0",
    installPermissions: env.DISCORD_BOT_PERMISSIONS,
    installScopes: parseDiscordInstallScopes(env.DISCORD_INSTALL_SCOPES),
    metricsToken: env.DISCORD_METRICS_TOKEN,
    port: Number(env.PORT ?? 3002),
    publicKey: env.DISCORD_PUBLIC_KEY,
    watApiBaseUrl: env.WAT_API_BASE_URL ?? "http://localhost:3000",
    watApiKey: env.WAT_API_KEY,
    watTeamId: env.WAT_TEAM_ID
  };
}

export function validateConfig(config: DiscordRuntimeConfig): void {
  if (!Number.isFinite(config.port) || config.port < 1) {
    throw new Error("PORT must be a positive number");
  }
  if (!config.publicKey) {
    throw new Error("DISCORD_PUBLIC_KEY is required");
  }
  if (!/^[a-f0-9]{64}$/i.test(config.publicKey)) {
    throw new Error("DISCORD_PUBLIC_KEY must be a 32-byte hex Ed25519 public key");
  }
  if (config.installStore === "postgres" && !config.databaseUrl) {
    throw new Error("DISCORD_DATABASE_URL, WAT_DATABASE_URL, or DATABASE_URL is required");
  }
}

export function createDiscordHttpHandler(
  config: DiscordRuntimeConfig,
  deps: DiscordRuntimeDeps = {}
) {
  const monitor = deps.monitor ?? defaultDiscordMonitor();
  return async (request: IncomingMessage, response: ServerResponse) => {
    const url = new URL(request.url ?? "/", "http://localhost");

    if (request.method === "GET" && url.pathname === "/healthz") {
      monitor.increment("discord_http_request_total", { path: "/healthz", status: 200 });
      writeJson(response, 200, {
        install_store: config.installStore ?? "json",
        service: "discord",
        status: "ok",
        wat_api_auth: {
          key: config.watApiKey ? "configured" : "missing",
          team_id: config.watTeamId ?? null
        },
        wat_api_base_url: config.watApiBaseUrl
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/discord/install") {
      try {
        const installUrl = buildDiscordInstallUrl({
          applicationId: config.applicationId,
          disableGuildSelect: config.installDisableGuildSelect,
          guildId: config.installGuildId,
          integrationType: config.installIntegrationType,
          permissions: config.installPermissions,
          scopes: config.installScopes
        });
        monitor.increment("discord_http_request_total", { path: "/discord/install", status: 302 });
        response.writeHead(302, { location: installUrl.toString() });
        response.end();
      } catch (error) {
        monitor.increment("discord_http_request_total", { path: "/discord/install", status: 503 });
        writeJson(response, 503, {
          error: "discord_install_not_configured",
          message: error instanceof Error ? error.message : "Discord install not configured"
        });
      }
      return;
    }

    if (request.method === "GET" && url.pathname === "/metrics") {
      if (!metricsAuthorized(config, request)) {
        monitor.increment("discord_http_request_total", { path: "/metrics", status: 401 });
        writeJson(response, 401, { error: "unauthorized" });
        return;
      }
      monitor.increment("discord_http_request_total", { path: "/metrics", status: 200 });
      writeText(response, 200, monitor.prometheus());
      return;
    }

    if (request.method === "POST" && url.pathname === "/discord/interactions") {
      const rawBody = await readRawBody(request);
      if (!verifyDiscordRequest(config, request, rawBody)) {
        monitor.increment("discord_http_request_total", {
          path: "/discord/interactions",
          status: 401
        });
        writeJson(response, 401, { error: "invalid_discord_signature" });
        return;
      }

      try {
        const payload = parseJsonBody(rawBody);
        const body = await handleDiscordInteraction(payload, config, deps, monitor);
        monitor.increment("discord_http_request_total", {
          path: "/discord/interactions",
          status: 200
        });
        writeJson(response, 200, body);
      } catch (error) {
        monitor.increment("discord_http_request_total", {
          path: "/discord/interactions",
          status: 500
        });
        monitor.log("discord_interaction_failed", {
          message: error instanceof Error ? error.message : "unknown error"
        });
        writeJson(response, 200, ephemeralResponse("wat request failed."));
      }
      return;
    }

    monitor.increment("discord_http_request_total", { path: url.pathname, status: 404 });
    writeJson(response, 404, { error: "not_found" });
  };
}

export async function startDiscordRuntime(config = configFromEnv()): Promise<void> {
  validateConfig(config);
  const server = createServer(createDiscordHttpHandler(config));
  await new Promise<void>((resolve) => server.listen(config.port, "0.0.0.0", resolve));
  console.log(JSON.stringify({ event: "discord_started", port: config.port }));
}

export function verifyDiscordSignature(input: {
  publicKey: string;
  rawBody: Buffer;
  signature: string;
  timestamp: string;
}): boolean {
  if (!/^[a-f0-9]{64}$/i.test(input.publicKey)) return false;
  if (!/^[a-f0-9]{128}$/i.test(input.signature)) return false;
  if (!input.timestamp.trim()) return false;

  try {
    const rawPublicKey = Buffer.from(input.publicKey, "hex");
    const key = createPublicKey({
      format: "der",
      key: Buffer.concat([ed25519PublicKeySpkiPrefix, rawPublicKey]),
      type: "spki"
    });
    return cryptoVerify(
      null,
      Buffer.concat([Buffer.from(input.timestamp, "utf8"), input.rawBody]),
      key,
      Buffer.from(input.signature, "hex")
    );
  } catch {
    return false;
  }
}

export function parseDiscordGuildWatTeamMap(value: string | undefined): Record<string, string> {
  const map: Record<string, string> = {};
  for (const part of value?.split(",") ?? []) {
    const [guildId, teamId] = part.split(":").map((item) => item.trim());
    if (guildId && teamId) map[guildId] = teamId;
  }
  return map;
}

function installStoreKind(
  value: string | undefined
): NonNullable<DiscordRuntimeConfig["installStore"]> {
  if (value === "postgres" || value === "memory" || value === "json") return value;
  return "json";
}

function csvEnv(value: string | undefined): string[] | undefined {
  const values = value
    ?.split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  return values && values.length > 0 ? values : undefined;
}

function defaultInstallStore(config: DiscordRuntimeConfig): DiscordInstallStore {
  const storeKind = config.installStore ?? "json";
  if (storeKind === "postgres") {
    if (!config.databaseUrl) throw new Error("database URL is required for Discord install store");
    return new PgDiscordInstallStore(config.databaseUrl);
  }
  if (storeKind === "memory") return new MemoryDiscordInstallStore();
  if (!config.installStorePath) throw new Error("DISCORD_INSTALL_STORE_PATH is required");
  return new JsonFileDiscordInstallStore(config.installStorePath);
}

async function handleDiscordInteraction(
  payload: DiscordInteraction,
  config: DiscordRuntimeConfig,
  deps: DiscordRuntimeDeps,
  monitor: DiscordMonitor
): Promise<InteractionResponse> {
  const type = payload.type;
  monitor.increment("discord_interaction_total", { type: type ?? "unknown" });
  if (type === DiscordInteractionType.PING) return { type: DiscordInteractionCallbackType.PONG };
  if (type !== DiscordInteractionType.APPLICATION_COMMAND) {
    return ephemeralResponse("Unsupported Discord interaction.");
  }
  return handleApplicationCommand(payload, config, deps, monitor);
}

async function handleApplicationCommand(
  interaction: DiscordInteraction,
  config: DiscordRuntimeConfig,
  deps: DiscordRuntimeDeps,
  monitor: DiscordMonitor
): Promise<InteractionResponse> {
  const command = interaction.data?.name;
  monitor.increment("discord_command_total", { command: command ?? "unknown" });
  const userId = interactionUserId(interaction);
  const resolved = await resolveWatInstall(config, deps, interaction.guild_id);
  const context = interactionContext(interaction);

  if (command === "wat") {
    const term = optionString(interaction.data, "term");
    if (!term) return ephemeralResponse("Use `/wat term:<term>`.");
    const entries = await lookup(config, deps, monitor, term, context, userId, resolved.watTeamId);
    return ephemeralResponse(renderLookupContent(term, entries));
  }

  if (command === "wat-alt") {
    const term = optionString(interaction.data, "term");
    if (!term) return ephemeralResponse("Use `/wat-alt term:<term>`.");
    const entries = await lookup(config, deps, monitor, term, context, userId, resolved.watTeamId);
    const top = entries[0];
    const alternatives = listAlternatives(top?.contemporaries);
    const resolvedAlternatives = await Promise.all(
      alternatives.map((alternative) =>
        lookup(config, deps, monitor, alternative, context, userId, resolved.watTeamId)
      )
    );
    return ephemeralResponse(
      renderAlternativesContent(term, top, alternatives, resolvedAlternatives)
    );
  }

  if (command === "wat-suggest") {
    if (!resolved.watTeamId)
      return ephemeralResponse("Discord server is not mapped to a wat team.");
    if (!config.watApiKey) return ephemeralResponse("Discord writes require WAT_API_KEY.");
    const definition = definitionFromOptions(interaction.data);
    if (!definition) {
      return ephemeralResponse(
        "Use `/wat-suggest term:<term> expansion:<expansion> meaning:<meaning>`."
      );
    }
    await postWatJson(
      config,
      deps,
      monitor,
      "/api/v1/suggestions",
      suggestionBody(interaction, definition),
      userId,
      resolved.watTeamId
    );
    return ephemeralResponse(
      `Suggested ${definition.term} as ${definition.expansion} for admin review.`
    );
  }

  if (command === "wat-define") {
    if (!resolved.watTeamId)
      return ephemeralResponse("Discord server is not mapped to a wat team.");
    if (!config.watApiKey) return ephemeralResponse("Discord writes require WAT_API_KEY.");
    if (!isAdminInteraction(interaction, config, resolved.install)) {
      return ephemeralResponse("Only configured Discord admins can define team entries.");
    }
    const definition = definitionFromOptions(interaction.data);
    if (!definition) {
      return ephemeralResponse(
        "Use `/wat-define term:<term> expansion:<expansion> meaning:<meaning>`."
      );
    }
    await postWatJson(
      config,
      deps,
      monitor,
      "/api/v1/custom-entries",
      customEntryBody(interaction, definition),
      userId,
      resolved.watTeamId
    );
    return ephemeralResponse(`Defined ${definition.term} as ${definition.expansion}.`);
  }

  if (command === "Explain acronyms") {
    const text = messageCommandText(interaction.data);
    const terms = acronymsIn(text);
    if (terms.length === 0) return ephemeralResponse("No acronyms found.");
    const lookups = await Promise.all(
      terms.map((term) => lookup(config, deps, monitor, term, text, userId, resolved.watTeamId))
    );
    return ephemeralResponse(renderAcronymList(lookups));
  }

  return ephemeralResponse("Unknown wat command.");
}

async function resolveWatInstall(
  config: DiscordRuntimeConfig,
  deps: DiscordRuntimeDeps,
  discordGuildId: string | undefined
): Promise<ResolvedInstall> {
  const normalizedGuildId = discordGuildId?.trim();
  let install: DiscordInstallRecord | null = null;
  if (normalizedGuildId) {
    install = await (deps.installStore ?? defaultInstallStore(config)).getByGuildId(
      normalizedGuildId
    );
    if (install?.watTeamId) return { install, watTeamId: install.watTeamId };
  }
  if (normalizedGuildId && config.discordGuildWatTeamMap?.[normalizedGuildId]) {
    return { install, watTeamId: config.discordGuildWatTeamMap[normalizedGuildId] };
  }
  return { install, watTeamId: config.watTeamId };
}

async function lookup(
  config: DiscordRuntimeConfig,
  deps: DiscordRuntimeDeps,
  monitor: DiscordMonitor,
  term: string,
  context = "",
  userId?: string,
  watTeamId?: string
): Promise<SearchEntry[]> {
  const client = deps.fetchLookup ?? fetch;
  const url = new URL("/api/v1/search", config.watApiBaseUrl);
  url.searchParams.set("q", term);
  url.searchParams.set("limit", "5");
  if (context.trim()) url.searchParams.set("context", context.trim());

  const response = await client(url, { headers: watAuthHeaders(config, userId, watTeamId) });
  monitor.increment("discord_lookup_total", { status: response.status });
  if (!response.ok) throw new Error(`wat lookup failed: ${response.status}`);
  const body = (await response.json()) as SearchResponse;
  return body.matches?.flatMap((match) => (match.entry ? [match.entry] : [])) ?? [];
}

async function postWatJson(
  config: DiscordRuntimeConfig,
  deps: DiscordRuntimeDeps,
  monitor: DiscordMonitor,
  pathname: string,
  body: unknown,
  userId: string | undefined,
  watTeamId: string
): Promise<void> {
  const client = deps.fetchWrite ?? fetch;
  const url = new URL(pathname, config.watApiBaseUrl);
  const response = await client(url, {
    body: JSON.stringify(body),
    headers: { "content-type": "application/json", ...watAuthHeaders(config, userId, watTeamId) },
    method: "POST"
  });
  monitor.increment("discord_write_total", { path: pathname, status: response.status });
  if (!response.ok) throw new Error(`wat write failed: ${response.status}`);
}

function watAuthHeaders(
  config: DiscordRuntimeConfig,
  userId?: string,
  watTeamId = config.watTeamId
): Record<string, string> {
  const headers: Record<string, string> = {};
  if (!config.watApiKey) return headers;
  headers.authorization = `Bearer ${config.watApiKey}`;
  if (watTeamId) headers["x-wat-team-id"] = watTeamId;
  if (userId) headers["x-wat-user-id"] = `discord:${userId}`;
  return headers;
}

interface ParsedDefinition {
  expansion: string;
  meaning: string;
  term: string;
}

function definitionFromOptions(
  data: DiscordApplicationCommandData | undefined
): ParsedDefinition | null {
  const term = optionString(data, "term");
  const expansion = optionString(data, "expansion");
  const meaning = optionString(data, "meaning");
  if (!term || !expansion || !meaning) return null;
  return {
    expansion,
    meaning,
    term: term.trim().toUpperCase()
  };
}

function suggestionBody(interaction: DiscordInteraction, definition: ParsedDefinition) {
  return {
    domains: domainsFor(interaction),
    expansion: definition.expansion,
    meaning: definition.meaning,
    source_url: discordSourceUrl(interaction),
    term: definition.term
  };
}

function customEntryBody(interaction: DiscordInteraction, definition: ParsedDefinition) {
  return {
    domains: domainsFor(interaction),
    expansion: definition.expansion,
    meaning: definition.meaning,
    mode: "upsert",
    scope: "team",
    sourceTitle: `Discord /wat-define by ${interactionUserId(interaction) ?? "unknown"}`,
    sourceUrl: discordSourceUrl(interaction),
    term: definition.term
  };
}

function optionString(
  data: DiscordApplicationCommandData | undefined,
  name: string
): string | null {
  const option = data?.options?.find((item) => item.name === name);
  return typeof option?.value === "string" && option.value.trim() ? option.value.trim() : null;
}

function interactionUserId(interaction: DiscordInteraction): string | undefined {
  return interaction.member?.user?.id ?? interaction.user?.id;
}

function interactionContext(interaction: DiscordInteraction): string {
  return [interaction.channel?.name, interaction.guild_id].filter(Boolean).join(" ");
}

function messageCommandText(data: DiscordApplicationCommandData | undefined): string {
  const messages = data?.resolved?.messages;
  if (!messages) return "";
  if (data?.target_id && messages[data.target_id]?.content)
    return messages[data.target_id]!.content!;
  return (
    Object.values(messages).find((message) => typeof message.content === "string")?.content ?? ""
  );
}

function acronymsIn(text: string): string[] {
  return Array.from(new Set(text.match(/\b[A-Z][A-Z0-9]{1,9}\b/g) ?? [])).slice(0, 8);
}

function isAdminInteraction(
  interaction: DiscordInteraction,
  config: DiscordRuntimeConfig,
  install: DiscordInstallRecord | null
): boolean {
  const userId = interactionUserId(interaction);
  if (userId && config.discordAdminUserIds?.includes(userId)) return true;
  if (hasPermission(interaction.member?.permissions, administratorPermission)) return true;
  const roles = new Set(interaction.member?.roles ?? []);
  const adminRoleIds = [...(config.discordAdminRoleIds ?? []), ...(install?.adminRoleIds ?? [])];
  return adminRoleIds.some((roleId) => roles.has(roleId));
}

function hasPermission(permissions: string | undefined, bit: bigint): boolean {
  if (!permissions) return false;
  try {
    return (BigInt(permissions) & bit) === bit;
  } catch {
    return false;
  }
}

function domainsFor(interaction: DiscordInteraction): string[] {
  return ["discord", interaction.guild_id, interaction.channel?.name].filter(
    (value): value is string => typeof value === "string" && value.trim().length > 0
  );
}

function discordSourceUrl(interaction: DiscordInteraction): string {
  const guildId = interaction.guild_id ?? "@me";
  const channelId = interaction.channel_id ?? interaction.channel?.id ?? "unknown";
  return `https://discord.com/channels/${encodeURIComponent(guildId)}/${encodeURIComponent(channelId)}`;
}

function listAlternatives(values?: string[]): string[] {
  const seen = new Set<string>();
  const alternatives: string[] = [];
  for (const value of values ?? []) {
    const alternative = value.trim();
    if (!alternative) continue;
    const key = alternative.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    alternatives.push(alternative);
  }
  return alternatives;
}

function renderLookupContent(term: string, entries: SearchEntry[]): string {
  const [top, ...rest] = entries;
  if (!top) return `No result for **${escapeMarkdown(term)}**.`;
  const title = `${escapeMarkdown(top.term ?? term)}: ${escapeMarkdown(top.expansions?.[0] ?? term)}`;
  const lines = [`**${title}**`];
  if (top.meaning_short) lines.push(escapeMarkdown(top.meaning_short));
  if (top.contemporaries && listAlternatives(top.contemporaries).length > 0) {
    lines.push(
      `Alternatives: ${listAlternatives(top.contemporaries).map(escapeMarkdown).join(", ")}`
    );
  }
  if (rest.length > 0) {
    lines.push(
      `Other matches: ${rest
        .slice(0, 4)
        .map((entry) => escapeMarkdown(entry.term ?? "Result"))
        .join(", ")}`
    );
  }
  return lines.join("\n");
}

function renderAlternativesContent(
  term: string,
  entry: SearchEntry | undefined,
  alternatives: string[],
  resolved: SearchEntry[][]
): string {
  const resolvedTerm = entry?.term ?? term;
  if (!entry) return `No result for **${escapeMarkdown(term)}**.`;
  if (alternatives.length === 0) return `No alternatives for **${escapeMarkdown(resolvedTerm)}**.`;
  const lines = [`Alternatives for **${escapeMarkdown(resolvedTerm)}**:`];
  for (const [index, alternative] of alternatives.entries()) {
    lines.push(renderAlternativeLine(alternative, resolved[index]?.[0]));
  }
  return lines.join("\n");
}

function renderAlternativeLine(alternative: string, entry: SearchEntry | undefined): string {
  const safeAlternative = escapeMarkdown(alternative);
  if (!entry) return `**${safeAlternative}**`;
  const title = `${escapeMarkdown(entry.term ?? alternative)}: ${escapeMarkdown(
    entry.expansions?.[0] ?? alternative
  )}`;
  return entry.meaning_short
    ? `**${title}** - ${escapeMarkdown(entry.meaning_short)}`
    : `**${title}**`;
}

function renderAcronymList(lookups: SearchEntry[][]): string {
  const entries = lookups.flatMap((matches) => matches.slice(0, 1));
  if (entries.length === 0) return "No glossary matches found.";
  return entries
    .map((entry) => {
      const term = entry.term ?? "Result";
      return `**${escapeMarkdown(term)}**: ${escapeMarkdown(entry.expansions?.[0] ?? term)}`;
    })
    .join("\n");
}

function escapeMarkdown(value: string): string {
  const markdownChars = new Set([
    "\\",
    "`",
    "*",
    "_",
    "{",
    "}",
    "[",
    "]",
    "(",
    ")",
    "#",
    "+",
    "-",
    ".",
    "!",
    "|",
    ">"
  ]);
  return Array.from(value, (char) => (markdownChars.has(char) ? `\\${char}` : char)).join("");
}

function ephemeralResponse(content: string): InteractionResponse {
  return {
    data: {
      allowed_mentions: { parse: [] },
      content: truncateDiscordContent(content),
      flags: DiscordMessageFlags.EPHEMERAL
    },
    type: DiscordInteractionCallbackType.CHANNEL_MESSAGE_WITH_SOURCE
  };
}

function truncateDiscordContent(value: string): string {
  return value.length > 1900 ? `${value.slice(0, 1897)}...` : value;
}

async function readRawBody(request: IncomingMessage): Promise<Buffer> {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

function parseJsonBody(rawBody: Buffer): DiscordInteraction {
  return JSON.parse(rawBody.toString("utf8")) as DiscordInteraction;
}

function verifyDiscordRequest(
  config: DiscordRuntimeConfig,
  request: IncomingMessage,
  rawBody: Buffer
): boolean {
  if (!config.publicKey) return false;
  const signature = headerValue(request, "x-signature-ed25519");
  const timestamp = headerValue(request, "x-signature-timestamp");
  if (!signature || !timestamp) return false;
  return verifyDiscordSignature({
    publicKey: config.publicKey,
    rawBody,
    signature,
    timestamp
  });
}

function headerValue(request: IncomingMessage, header: string): string | undefined {
  const value = request.headers[header];
  return Array.isArray(value) ? value[0] : value;
}

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

function writeText(response: ServerResponse, status: number, body: string): void {
  response.writeHead(status, { "content-type": "text/plain; charset=utf-8" });
  response.end(body);
}

function metricsAuthorized(config: DiscordRuntimeConfig, request: IncomingMessage): boolean {
  if (!config.metricsToken) return false;
  const authorization = headerValue(request, "authorization");
  if (authorization === `Bearer ${config.metricsToken}`) return true;
  return headerValue(request, "x-discord-metrics-token") === config.metricsToken;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await startDiscordRuntime();
}
