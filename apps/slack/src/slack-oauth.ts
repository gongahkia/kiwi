import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

import { encryptToken } from "./token-encryption.js";
import type { SlackInstallRecord } from "./slack-install-store.js";

export const slackRequiredBotScopes = [
  "commands",
  "chat:write",
  "app_mentions:read",
  "users:read.email"
] as const;
export const slackRequiredUserScopes = ["identity.basic", "identity.email"] as const;

const defaultStateMaxAgeMs = 10 * 60_000;

export interface SlackOAuthConfig {
  botScopes?: string[];
  clientId?: string;
  clientSecret?: string;
  redirectUri?: string;
  slackTeamWatTeamMap?: Record<string, string>;
  stateSecret?: string;
  tokenEncryptionKey?: string;
  userScopes?: string[];
  watTeamId?: string;
}

interface SlackOAuthStatePayload {
  issuedAt: number;
  nonce: string;
}

interface SlackOAuthAccessResponse {
  access_token?: string;
  app_id?: string;
  authed_user?: {
    access_token?: string;
    id?: string;
    scope?: string;
    token_type?: string;
  };
  bot_user_id?: string;
  enterprise?: {
    id?: string;
    name?: string;
  };
  error?: string;
  ok?: boolean;
  scope?: string;
  team?: {
    id?: string;
    name?: string;
  };
}

export function missingSlackOAuthConfig(config: SlackOAuthConfig): string[] {
  const required: Array<{ name: string; value?: string }> = [
    { name: "SLACK_CLIENT_ID", value: config.clientId },
    { name: "SLACK_CLIENT_SECRET", value: config.clientSecret },
    { name: "SLACK_STATE_SECRET", value: config.stateSecret },
    { name: "SLACK_TOKEN_ENCRYPTION_KEY", value: config.tokenEncryptionKey }
  ];
  return required.filter((item) => !item.value).map((item) => item.name);
}

export function createSlackOAuthState(
  stateSecret: string,
  now = Date.now(),
  nonce = randomBytes(16).toString("base64url")
): string {
  const payload = base64urlJson({ issuedAt: now, nonce });
  return `${payload}.${stateSignature(payload, stateSecret)}`;
}

export function verifySlackOAuthState(
  state: string,
  stateSecret: string,
  now = Date.now(),
  maxAgeMs = defaultStateMaxAgeMs
): SlackOAuthStatePayload {
  const [payload, signature] = state.split(".");
  if (
    !payload ||
    !signature ||
    !timingSafeStringEqual(signature, stateSignature(payload, stateSecret))
  ) {
    throw new Error("invalid Slack OAuth state");
  }

  const decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as unknown;
  if (!decoded || typeof decoded !== "object") throw new Error("invalid Slack OAuth state");
  const candidate = decoded as Partial<SlackOAuthStatePayload>;
  if (typeof candidate.issuedAt !== "number" || typeof candidate.nonce !== "string") {
    throw new Error("invalid Slack OAuth state");
  }
  if (now - candidate.issuedAt > maxAgeMs || candidate.issuedAt - now > 60_000) {
    throw new Error("expired Slack OAuth state");
  }

  return { issuedAt: candidate.issuedAt, nonce: candidate.nonce };
}

export function buildSlackInstallUrl(config: SlackOAuthConfig, state: string): URL {
  if (!config.clientId) throw new Error("SLACK_CLIENT_ID is required");
  const url = new URL("https://slack.com/oauth/v2/authorize");
  url.searchParams.set("client_id", config.clientId);
  url.searchParams.set("scope", (config.botScopes ?? slackRequiredBotScopes).join(","));
  url.searchParams.set("user_scope", (config.userScopes ?? slackRequiredUserScopes).join(","));
  url.searchParams.set("state", state);
  if (config.redirectUri) url.searchParams.set("redirect_uri", config.redirectUri);
  return url;
}

export async function exchangeSlackOAuthCode(
  config: SlackOAuthConfig,
  code: string,
  fetchOAuth: typeof fetch = fetch,
  now = Date.now()
): Promise<SlackInstallRecord> {
  if (!config.clientId) throw new Error("SLACK_CLIENT_ID is required");
  if (!config.clientSecret) throw new Error("SLACK_CLIENT_SECRET is required");

  const form = new URLSearchParams({
    client_id: config.clientId,
    client_secret: config.clientSecret,
    code
  });
  if (config.redirectUri) form.set("redirect_uri", config.redirectUri);

  const response = await fetchOAuth("https://slack.com/api/oauth.v2.access", {
    body: form,
    headers: { "content-type": "application/x-www-form-urlencoded" },
    method: "POST"
  });
  if (!response.ok) throw new Error(`Slack OAuth exchange failed: ${response.status}`);

  return slackInstallRecordFromOAuthResponse(
    (await response.json()) as SlackOAuthAccessResponse,
    config,
    now
  );
}

export function slackInstallRecordFromOAuthResponse(
  body: SlackOAuthAccessResponse,
  config: SlackOAuthConfig,
  now = Date.now()
): SlackInstallRecord {
  if (!body.ok) throw new Error(`Slack OAuth failed: ${body.error ?? "unknown_error"}`);
  if (!body.access_token) throw new Error("Slack OAuth response missing bot token");
  if (!body.team?.id) throw new Error("Slack OAuth response missing team id");
  if (!body.bot_user_id) throw new Error("Slack OAuth response missing bot user id");
  if (!body.app_id) throw new Error("Slack OAuth response missing app id");
  if (!body.authed_user?.id) throw new Error("Slack OAuth response missing authed user id");
  if (!config.tokenEncryptionKey) throw new Error("SLACK_TOKEN_ENCRYPTION_KEY is required");

  const installedAt = new Date(now).toISOString();
  const userToken = body.authed_user.access_token
    ? encryptToken(body.authed_user.access_token, config.tokenEncryptionKey)
    : undefined;

  return {
    appId: body.app_id,
    botScopes: scopesFrom(body.scope),
    botToken: encryptToken(body.access_token, config.tokenEncryptionKey),
    botUserId: body.bot_user_id,
    enterpriseId: body.enterprise?.id,
    enterpriseName: body.enterprise?.name,
    installedAt,
    installerSlackUserId: body.authed_user.id,
    slackTeamId: body.team.id,
    slackTeamName: body.team.name,
    updatedAt: installedAt,
    userScopes: scopesFrom(body.authed_user.scope),
    userToken,
    watTeamId: watTeamIdForSlackTeam(body.team.id, config)
  };
}

export function parseSlackTeamWatTeamMap(value: string | undefined): Record<string, string> {
  if (!value?.trim()) return {};
  const map: Record<string, string> = {};
  for (const item of value.split(",")) {
    const [slackTeamId, watTeamId] = item.split(/[:=]/).map((part) => part.trim());
    if (!slackTeamId || !watTeamId) {
      throw new Error("WAT_SLACK_TEAM_MAP must use T123:team_123 pairs");
    }
    map[slackTeamId] = watTeamId;
  }
  return map;
}

export function watTeamIdForSlackTeam(slackTeamId: string, config: SlackOAuthConfig): string {
  const mapped = config.slackTeamWatTeamMap?.[slackTeamId];
  if (mapped) return mapped;
  if (config.watTeamId) return config.watTeamId;
  throw new Error(`missing wat team mapping for Slack team ${slackTeamId}`);
}

function scopesFrom(value: string | undefined): string[] {
  return (value ?? "")
    .split(",")
    .map((scope) => scope.trim())
    .filter(Boolean);
}

function base64urlJson(payload: SlackOAuthStatePayload): string {
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
}

function stateSignature(payload: string, stateSecret: string): string {
  if (!stateSecret) throw new Error("SLACK_STATE_SECRET is required");
  return createHmac("sha256", stateSecret).update(payload, "utf8").digest("base64url");
}

function timingSafeStringEqual(left: string, right: string): boolean {
  const leftBytes = Buffer.from(left, "utf8");
  const rightBytes = Buffer.from(right, "utf8");
  return leftBytes.length === rightBytes.length && timingSafeEqual(leftBytes, rightBytes);
}
