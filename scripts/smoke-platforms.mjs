#!/usr/bin/env node

const platform = process.argv[2] ?? "all";
const validPlatforms = new Set(["all", "discord", "slack", "teams"]);
const writeEnabled = truthy(process.env.SMOKE_WRITE);
const installEnabled = truthy(process.env.DISCORD_SMOKE_INSTALL);
const timeoutMs = Number(process.env.SMOKE_TIMEOUT_MS ?? "10000");
const failures = [];

if (!validPlatforms.has(platform)) {
  failNow(`unknown platform "${platform}"; expected all, slack, teams, or discord`);
}

function truthy(value) {
  return ["1", "true", "yes", "on"].includes(String(value ?? "").toLowerCase());
}

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) failNow(`${name} is required`);
  return value;
}

function optionalEnv(name) {
  return process.env[name]?.trim() || null;
}

function failNow(message) {
  console.error(`smoke config failed: ${message}`);
  process.exit(2);
}

function watHeaders(surface) {
  const headers = {
    authorization: `Bearer ${requiredEnv("WAT_API_KEY")}`,
    "x-wat-user-id": `${surface}:smoke`
  };
  const teamId = optionalEnv("WAT_TEAM_ID");
  if (teamId) headers["x-wat-team-id"] = teamId;
  return headers;
}

function baseUrl(name) {
  return requiredEnv(name).replace(/\/+$/, "");
}

async function requestJson(label, url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: {
      accept: "application/json",
      ...(init.body ? { "content-type": "application/json" } : {}),
      ...(init.headers ?? {})
    },
    signal: AbortSignal.timeout(timeoutMs)
  });
  const text = await response.text();
  const body = text ? safeJson(text) : null;
  if (!response.ok) {
    throw new Error(`${label} returned ${response.status}: ${text.slice(0, 500)}`);
  }
  return body;
}

function safeJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return { text };
  }
}

async function check(label, fn) {
  try {
    await fn();
    console.log(`ok ${label}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    failures.push(`${label}: ${message}`);
    console.error(`fail ${label}: ${message}`);
  }
}

async function checkWatSearch(surface) {
  const apiBase = baseUrl("WAT_API_BASE_URL");
  const url = new URL("/api/v1/search", apiBase);
  url.searchParams.set("q", "API");
  url.searchParams.set("limit", "1");
  const body = await requestJson(`${surface} wat search`, url, {
    headers: watHeaders(surface)
  });
  if (!Array.isArray(body?.matches)) throw new Error("missing matches array");
}

async function checkSuggestion(surface) {
  if (!writeEnabled) {
    console.log(`skip ${surface} suggestion write; set SMOKE_WRITE=true to enable`);
    return;
  }
  const apiBase = baseUrl("WAT_API_BASE_URL");
  const body = await requestJson(`${surface} suggestion`, `${apiBase}/api/v1/suggestions`, {
    body: JSON.stringify({
      domains: ["smoke"],
      expansion: "Smoke Test Definition",
      meaning: `Live ${surface} smoke suggestion.`,
      source_title: `${surface} smoke`,
      source_url: "https://example.com/wat-smoke",
      term: "SMOKE"
    }),
    headers: watHeaders(surface),
    method: "POST"
  });
  if (body?.suggestion?.status !== "pending") throw new Error("suggestion was not queued");
}

async function checkHealth(label, envName) {
  const origin = optionalEnv(envName);
  if (!origin) {
    console.log(`skip ${label} health; ${envName} not set`);
    return;
  }
  await requestJson(`${label} health`, `${origin.replace(/\/+$/, "")}/healthz`);
}

async function checkMetrics(label, originEnv, tokenEnv) {
  const origin = optionalEnv(originEnv);
  const token = optionalEnv(tokenEnv);
  if (!origin || !token) {
    console.log(`skip ${label} metrics; ${originEnv} or ${tokenEnv} not set`);
    return;
  }
  await fetch(`${origin.replace(/\/+$/, "")}/metrics`, {
    headers: { authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(timeoutMs)
  }).then(async (response) => {
    const text = await response.text();
    if (!response.ok) throw new Error(`${label} metrics returned ${response.status}: ${text}`);
    if (!text.trim()) throw new Error("metrics response was empty");
  });
}

async function checkSlackAuth() {
  const token = optionalEnv("SLACK_BOT_TOKEN");
  if (!token) {
    console.log("skip Slack auth.test; SLACK_BOT_TOKEN not set");
    return;
  }
  const body = await requestJson("Slack auth.test", "https://slack.com/api/auth.test", {
    headers: { authorization: `Bearer ${token}` }
  });
  if (body?.ok !== true) throw new Error(body?.error ?? "Slack auth.test failed");
}

async function checkDiscordAuth() {
  const token = optionalEnv("DISCORD_BOT_TOKEN");
  if (!token) {
    console.log("skip Discord bot auth; DISCORD_BOT_TOKEN not set");
    return;
  }
  const body = await requestJson("Discord /users/@me", "https://discord.com/api/v10/users/@me", {
    headers: { authorization: `Bot ${token}` }
  });
  if (!body?.id) throw new Error("Discord bot identity missing");
}

async function checkDiscordInstallMapping() {
  if (!installEnabled) {
    console.log("skip Discord install mapping; set DISCORD_SMOKE_INSTALL=true to enable");
    return;
  }
  const guildId = requiredEnv("DISCORD_SMOKE_GUILD_ID");
  const applicationId = requiredEnv("DISCORD_APPLICATION_ID");
  const apiBase = baseUrl("WAT_API_BASE_URL");
  const body = await requestJson(
    "Discord install mapping",
    `${apiBase}/api/v1/discord/installations`,
    {
      body: JSON.stringify({
        application_id: applicationId,
        discord_guild_id: guildId,
        guild_name: "wat smoke"
      }),
      headers: watHeaders("discord"),
      method: "POST"
    }
  );
  if (body?.install?.discord_guild_id !== guildId) throw new Error("install mapping not returned");
}

async function runSlack() {
  await check("Slack wat search", () => checkWatSearch("slack"));
  await check("Slack suggestion write", () => checkSuggestion("slack"));
  await check("Slack runtime health", () => checkHealth("Slack", "SLACK_PUBLIC_URL"));
  await check("Slack runtime metrics", () =>
    checkMetrics("Slack", "SLACK_PUBLIC_URL", "SLACK_METRICS_TOKEN")
  );
  await check("Slack bot auth", checkSlackAuth);
}

async function runTeams() {
  await check("Teams message-extension search", async () => {
    const apiBase = baseUrl("WAT_API_BASE_URL");
    const url = new URL("/api/v1/teams/search", apiBase);
    url.searchParams.set("q", "API");
    const body = await requestJson("Teams search", url, {
      headers: watHeaders("teams")
    });
    if (!Array.isArray(body?.results)) throw new Error("missing results array");
  });
  await check("Teams metrics", async () => {
    const apiBase = baseUrl("WAT_API_BASE_URL");
    const token = optionalEnv("TEAMS_METRICS_TOKEN");
    if (!token) {
      console.log("skip Teams metrics; TEAMS_METRICS_TOKEN not set");
      return;
    }
    await requestJson("Teams metrics", `${apiBase}/api/v1/teams/metrics`, {
      headers: { authorization: `Bearer ${token}` }
    });
  });
}

async function runDiscord() {
  await check("Discord wat search", () => checkWatSearch("discord"));
  await check("Discord suggestion write", () => checkSuggestion("discord"));
  await check("Discord runtime health", () => checkHealth("Discord", "DISCORD_PUBLIC_URL"));
  await check("Discord runtime metrics", () =>
    checkMetrics("Discord", "DISCORD_PUBLIC_URL", "DISCORD_METRICS_TOKEN")
  );
  await check("Discord bot auth", checkDiscordAuth);
  await check("Discord install mapping", checkDiscordInstallMapping);
}

if (platform === "all" || platform === "slack") await runSlack();
if (platform === "all" || platform === "teams") await runTeams();
if (platform === "all" || platform === "discord") await runDiscord();

if (failures.length > 0) {
  console.error("");
  console.error("Smoke failures:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}
