import { createHmac, timingSafeEqual } from "node:crypto";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { App } from "@slack/bolt";

import {
  buildSlackInstallUrl,
  createSlackOAuthState,
  exchangeSlackOAuthCode,
  missingSlackOAuthConfig,
  parseSlackTeamWatTeamMap,
  verifySlackOAuthState
} from "./slack-oauth.js";
import {
  JsonFileSlackAutoDetectStore,
  MemorySlackAutoDetectStore,
  type SlackAutoDetectStore
} from "./auto-detect-settings.js";
import {
  JsonFileSlackInstallStore,
  MemorySlackInstallStore,
  PgSlackInstallStore,
  type SlackInstallStore
} from "./slack-install-store.js";
import { defaultSlackMonitor, type SlackMonitor } from "./slack-monitoring.js";
import { registerWatBoltHandlers } from "./wat-bolt.js";

export interface SlackRuntimeConfig {
  appToken?: string;
  autoDetectStore?: "json" | "memory";
  autoDetectStorePath?: string;
  botToken?: string;
  clientId?: string;
  clientSecret?: string;
  databaseUrl?: string;
  httpMode: boolean;
  installStore?: "json" | "memory" | "postgres";
  installStorePath?: string;
  metricsToken?: string;
  port: number;
  redirectUri?: string;
  signingSecret?: string;
  slackAdminUserIds?: string[];
  slackTeamWatTeamMap?: Record<string, string>;
  socketMode: boolean;
  stateSecret?: string;
  tokenEncryptionKey?: string;
  watApiKey?: string;
  watApiBaseUrl: string;
  watTeamId?: string;
}

export interface SlackRuntimeDeps {
  autoDetectStore?: SlackAutoDetectStore;
  fetchOAuth?: typeof fetch;
  installStore?: SlackInstallStore;
  monitor?: SlackMonitor;
  now?: () => number;
}

export function configFromEnv(env: NodeJS.ProcessEnv = process.env): SlackRuntimeConfig {
  return {
    appToken: env.SLACK_APP_TOKEN,
    autoDetectStore: autoDetectStoreKind(env.SLACK_AUTO_DETECT_STORE),
    autoDetectStorePath: env.SLACK_AUTO_DETECT_STORE_PATH ?? ".wat-slack-auto-detect.json",
    botToken: env.SLACK_BOT_TOKEN,
    clientId: env.SLACK_CLIENT_ID,
    clientSecret: env.SLACK_CLIENT_SECRET,
    databaseUrl: env.SLACK_DATABASE_URL ?? env.WAT_DATABASE_URL ?? env.DATABASE_URL,
    httpMode: env.SLACK_HTTP_MODE !== "false",
    installStore: installStoreKind(env.SLACK_INSTALL_STORE),
    installStorePath: env.SLACK_INSTALL_STORE_PATH ?? ".wat-slack-installs.json",
    metricsToken: env.SLACK_METRICS_TOKEN,
    port: Number(env.PORT ?? 3001),
    redirectUri: env.SLACK_REDIRECT_URI,
    signingSecret: env.SLACK_SIGNING_SECRET,
    slackAdminUserIds: csvEnv(env.SLACK_ADMIN_USER_IDS),
    slackTeamWatTeamMap: parseSlackTeamWatTeamMap(env.WAT_SLACK_TEAM_MAP),
    socketMode: env.SLACK_SOCKET_MODE === "true",
    stateSecret: env.SLACK_STATE_SECRET,
    tokenEncryptionKey: env.SLACK_TOKEN_ENCRYPTION_KEY,
    watApiKey: env.WAT_API_KEY,
    watApiBaseUrl: env.WAT_API_BASE_URL ?? "http://localhost:3000",
    watTeamId: env.WAT_TEAM_ID
  };
}

export function validateConfig(config: SlackRuntimeConfig): void {
  if (!Number.isFinite(config.port) || config.port < 1) {
    throw new Error("PORT must be a positive number");
  }
  if (config.socketMode && !config.appToken) {
    throw new Error("SLACK_APP_TOKEN is required when SLACK_SOCKET_MODE=true");
  }
  if (config.socketMode && !config.botToken) {
    throw new Error("SLACK_BOT_TOKEN is required when SLACK_SOCKET_MODE=true");
  }
  if (config.httpMode && !config.signingSecret) {
    throw new Error("SLACK_SIGNING_SECRET is required when Slack HTTP mode is enabled");
  }
  if (config.installStore === "postgres" && !config.databaseUrl) {
    throw new Error("SLACK_DATABASE_URL, WAT_DATABASE_URL, or DATABASE_URL is required");
  }
}

export function createSlackHttpHandler(config: SlackRuntimeConfig, deps: SlackRuntimeDeps = {}) {
  const monitor = deps.monitor ?? defaultSlackMonitor();
  return async (request: IncomingMessage, response: ServerResponse) => {
    const url = new URL(request.url ?? "/", "http://localhost");
    if (request.method === "GET" && url.pathname === "/healthz") {
      monitor.increment("slack_http_request_total", { path: "/healthz", status: 200 });
      writeJson(response, 200, {
        mode: {
          http: config.httpMode ? "ok" : "disabled",
          socket: config.socketMode ? "ok" : "disabled"
        },
        oauth: {
          install_store: config.installStore ?? "json",
          missing: missingSlackOAuthConfig(config)
        },
        service: "slack",
        status: "ok",
        slack_auth: {
          bot_token: config.botToken ? "configured" : "missing"
        },
        wat_api_auth: {
          key: config.watApiKey ? "configured" : "missing",
          team_id: config.watTeamId ?? null
        },
        wat_api_base_url: config.watApiBaseUrl
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/metrics") {
      if (!metricsAuthorized(config, request)) {
        monitor.increment("slack_http_request_total", { path: "/metrics", status: 401 });
        writeJson(response, 401, { error: "unauthorized" });
        return;
      }
      monitor.increment("slack_http_request_total", { path: "/metrics", status: 200 });
      writeText(response, 200, monitor.prometheus());
      return;
    }

    if (request.method === "GET" && url.pathname === "/slack/install") {
      handleSlackInstall(config, response, monitor, deps.now?.() ?? Date.now());
      return;
    }

    if (request.method === "GET" && url.pathname === "/slack/oauth/callback") {
      const installStore = deps.installStore ?? defaultInstallStore(config);
      await handleSlackOauthCallback(config, installStore, response, url, { ...deps, monitor });
      return;
    }

    if (request.method === "POST" && url.pathname === "/slack/events") {
      const rawBody = await readRawBody(request);
      if (!verifySlackRequest(config, request, rawBody)) {
        monitor.increment("slack_http_request_total", {
          path: "/slack/events",
          status: 401
        });
        writeJson(response, 401, { error: "invalid_slack_signature" });
        return;
      }

      const payload = parseJsonBody(rawBody);
      if (payload?.type === "url_verification" && typeof payload.challenge === "string") {
        monitor.increment("slack_http_request_total", {
          path: "/slack/events",
          status: 200
        });
        writeJson(response, 200, { challenge: payload.challenge });
        return;
      }

      if (payload?.type === "event_callback") {
        const installStore = deps.installStore ?? defaultInstallStore(config);
        await handleSlackEventCallback(payload, installStore, monitor);
      }

      monitor.increment("slack_http_request_total", { path: "/slack/events", status: 202 });
      writeJson(response, 202, { ok: true });
      return;
    }

    monitor.increment("slack_http_request_total", { path: url.pathname, status: 404 });
    writeJson(response, 404, { error: "not_found" });
  };
}

export async function startSlackRuntime(config = configFromEnv()): Promise<void> {
  validateConfig(config);
  if (config.socketMode) {
    await createWatSlackApp(config).start();
  }

  if (!config.httpMode) {
    await new Promise(() => undefined);
    return;
  }

  const server = createServer(createSlackHttpHandler(config));
  await new Promise<void>((resolve) => server.listen(config.port, "0.0.0.0", resolve));
  console.log(
    JSON.stringify({
      event: "slack_started",
      http: true,
      port: config.port,
      socket: config.socketMode
    })
  );
}

export function createWatSlackApp(config: SlackRuntimeConfig): App {
  validateConfig({ ...config, socketMode: true });
  const installStore = defaultInstallStore(config);
  const autoDetectStore = defaultAutoDetectStore(config);
  const app = new App({
    appToken: config.appToken,
    socketMode: true,
    token: config.botToken
  });

  registerWatBoltHandlers(app, {
    autoDetectStore,
    installStore,
    monitor: defaultSlackMonitor(),
    slackAdminUserIds: config.slackAdminUserIds,
    slackBotToken: config.botToken,
    slackTeamWatTeamMap: config.slackTeamWatTeamMap,
    watApiKey: config.watApiKey,
    watApiBaseUrl: config.watApiBaseUrl,
    watTeamId: config.watTeamId
  });

  return app;
}

function defaultAutoDetectStore(config: SlackRuntimeConfig): SlackAutoDetectStore {
  const storeKind = config.autoDetectStore ?? "json";
  if (storeKind === "memory") return new MemorySlackAutoDetectStore();
  if (!config.autoDetectStorePath) throw new Error("SLACK_AUTO_DETECT_STORE_PATH is required");
  return new JsonFileSlackAutoDetectStore(config.autoDetectStorePath);
}

function csvEnv(value: string | undefined): string[] | undefined {
  const values = value
    ?.split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  return values && values.length > 0 ? values : undefined;
}

function defaultInstallStore(config: SlackRuntimeConfig): SlackInstallStore {
  const storeKind = config.installStore ?? "json";
  if (storeKind === "postgres") {
    if (!config.databaseUrl) throw new Error("database URL is required for Slack install store");
    return new PgSlackInstallStore(config.databaseUrl);
  }
  if (storeKind === "memory") return new MemorySlackInstallStore();
  if (!config.installStorePath) throw new Error("SLACK_INSTALL_STORE_PATH is required");
  return new JsonFileSlackInstallStore(config.installStorePath);
}

function installStoreKind(
  value: string | undefined
): NonNullable<SlackRuntimeConfig["installStore"]> {
  if (value === "postgres" || value === "memory" || value === "json") return value;
  return "json";
}

function autoDetectStoreKind(
  value: string | undefined
): NonNullable<SlackRuntimeConfig["autoDetectStore"]> {
  if (value === "memory" || value === "json") return value;
  return "json";
}

function handleSlackInstall(
  config: SlackRuntimeConfig,
  response: ServerResponse,
  monitor: SlackMonitor,
  now: number
): void {
  const missing = missingSlackOAuthConfig(config);
  if (missing.length > 0) {
    monitor.increment("slack_oauth_callback_total", { outcome: "not_configured" });
    writeJson(response, 503, { error: "slack_oauth_not_configured", missing });
    return;
  }

  const state = createSlackOAuthState(config.stateSecret!, now);
  monitor.increment("slack_http_request_total", { path: "/slack/install", status: 302 });
  response.writeHead(302, { location: buildSlackInstallUrl(config, state).toString() });
  response.end();
}

async function handleSlackOauthCallback(
  config: SlackRuntimeConfig,
  installStore: SlackInstallStore,
  response: ServerResponse,
  url: URL,
  deps: SlackRuntimeDeps
): Promise<void> {
  const monitor = deps.monitor ?? defaultSlackMonitor();
  const missing = missingSlackOAuthConfig(config);
  if (missing.length > 0) {
    monitor.increment("slack_oauth_callback_total", { outcome: "not_configured" });
    writeJson(response, 503, { error: "slack_oauth_not_configured", missing });
    return;
  }

  const slackError = url.searchParams.get("error");
  if (slackError) {
    monitor.increment("slack_oauth_callback_total", { outcome: "denied" });
    writeJson(response, 400, { error: "slack_oauth_denied", slack_error: slackError });
    return;
  }

  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  if (!code || !state) {
    monitor.increment("slack_oauth_callback_total", { outcome: "invalid_callback" });
    writeJson(response, 400, { error: "invalid_slack_oauth_callback" });
    return;
  }

  try {
    verifySlackOAuthState(state, config.stateSecret!, deps.now?.() ?? Date.now());
    const install = await exchangeSlackOAuthCode(
      config,
      code,
      deps.fetchOAuth ?? fetch,
      deps.now?.() ?? Date.now()
    );
    await installStore.upsert(install);
    monitor.increment("slack_oauth_callback_total", { outcome: "success" });
    monitor.log("slack_oauth_installed", {
      slack_team_id: install.slackTeamId,
      wat_team_id: install.watTeamId
    });
    writeHtml(
      response,
      200,
      `wat installed for Slack workspace ${escapeHtml(install.slackTeamName ?? install.slackTeamId)}.`
    );
  } catch (error) {
    monitor.increment("slack_oauth_callback_total", { outcome: "failed" });
    writeJson(response, 400, {
      error: "slack_oauth_failed",
      message: error instanceof Error ? error.message : "unknown error"
    });
  }
}

async function handleSlackEventCallback(
  payload: Record<string, unknown>,
  installStore: SlackInstallStore,
  monitor: SlackMonitor
): Promise<void> {
  const event =
    payload.event && typeof payload.event === "object"
      ? (payload.event as Record<string, unknown>)
      : null;
  const eventType = typeof event?.type === "string" ? event.type : "unknown";
  monitor.increment("slack_event_total", { type: eventType });

  if (
    eventType !== "app_uninstalled" &&
    eventType !== "tokens_revoked" &&
    eventType !== "app_uninstalled_team"
  ) {
    return;
  }

  const slackTeamId = slackTeamIdFromEventPayload(payload);
  if (!slackTeamId) {
    monitor.increment("slack_uninstall_total", { outcome: "missing_team", type: eventType });
    return;
  }

  await installStore.deleteBySlackTeamId(slackTeamId);
  monitor.increment("slack_uninstall_total", { outcome: "deleted", type: eventType });
  monitor.log("slack_install_deleted", { slack_team_id: slackTeamId, type: eventType });
}

function slackTeamIdFromEventPayload(payload: Record<string, unknown>): string | null {
  const teamId = payload.team_id;
  if (typeof teamId === "string" && teamId.trim()) return teamId.trim();
  const event = payload.event as Record<string, unknown> | undefined;
  const eventTeamId = event?.team_id;
  return typeof eventTeamId === "string" && eventTeamId.trim() ? eventTeamId.trim() : null;
}

async function readRawBody(request: IncomingMessage): Promise<Buffer> {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

function parseJsonBody(rawBody: Buffer): Record<string, unknown> | null {
  if (rawBody.length === 0) return null;
  return JSON.parse(rawBody.toString("utf8")) as Record<string, unknown>;
}

function verifySlackRequest(
  config: SlackRuntimeConfig,
  request: IncomingMessage,
  rawBody: Buffer
): boolean {
  if (!config.signingSecret) return false;

  const timestamp = headerValue(request, "x-slack-request-timestamp");
  const signature = headerValue(request, "x-slack-signature");
  if (!timestamp || !signature) return false;

  const timestampSeconds = Number(timestamp);
  if (!Number.isInteger(timestampSeconds)) return false;

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - timestampSeconds) > 60 * 5) return false;

  const baseString = `v0:${timestamp}:${rawBody.toString("utf8")}`;
  const expected = `v0=${createHmac("sha256", config.signingSecret)
    .update(baseString, "utf8")
    .digest("hex")}`;
  return timingSafeStringEqual(expected, signature);
}

function headerValue(request: IncomingMessage, header: string): string | undefined {
  const value = request.headers[header];
  return Array.isArray(value) ? value[0] : value;
}

function timingSafeStringEqual(left: string, right: string): boolean {
  const leftBytes = Buffer.from(left, "utf8");
  const rightBytes = Buffer.from(right, "utf8");
  return leftBytes.length === rightBytes.length && timingSafeEqual(leftBytes, rightBytes);
}

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

function writeText(response: ServerResponse, status: number, body: string): void {
  response.writeHead(status, { "content-type": "text/plain; charset=utf-8" });
  response.end(body);
}

function writeHtml(response: ServerResponse, status: number, body: string): void {
  response.writeHead(status, { "content-type": "text/html; charset=utf-8" });
  response.end(`<!doctype html><meta charset="utf-8"><title>wat Slack</title><p>${body}</p>`);
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function metricsAuthorized(config: SlackRuntimeConfig, request: IncomingMessage): boolean {
  if (!config.metricsToken) return false;
  const authorization = headerValue(request, "authorization");
  if (authorization === `Bearer ${config.metricsToken}`) return true;
  return headerValue(request, "x-slack-metrics-token") === config.metricsToken;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await startSlackRuntime();
}
