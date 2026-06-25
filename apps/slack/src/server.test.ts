import { createHmac } from "node:crypto";
import { createServer } from "node:http";
import { afterEach, describe, expect, it } from "vitest";

import { decryptToken, encryptToken } from "./token-encryption.js";
import { createSlackOAuthState } from "./slack-oauth.js";
import { MemorySlackInstallStore } from "./slack-install-store.js";
import { InMemorySlackMonitor } from "./slack-monitoring.js";
import { configFromEnv, createSlackHttpHandler, validateConfig } from "./server.js";

const servers: ReturnType<typeof createServer>[] = [];

afterEach(async () => {
  await Promise.all(
    servers.map(
      (server) =>
        new Promise<void>((resolve, reject) =>
          server.close((error) => (error ? reject(error) : resolve()))
        )
    )
  );
  servers.length = 0;
});

describe("slack runtime", () => {
  it("serves health for HTTP and socket mode", async () => {
    const url = await listen({
      appToken: "xapp-test",
      botToken: "xoxb-test",
      httpMode: true,
      port: 0,
      signingSecret: "test-secret",
      socketMode: true,
      watApiBaseUrl: "http://web:3000"
    });

    const response = await fetch(new URL("/healthz", url));

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      mode: { http: "ok", socket: "ok" },
      oauth: {
        missing: [
          "SLACK_CLIENT_ID",
          "SLACK_CLIENT_SECRET",
          "SLACK_STATE_SECRET",
          "SLACK_TOKEN_ENCRYPTION_KEY"
        ]
      },
      service: "slack",
      status: "ok",
      wat_api_auth: { key: "missing", team_id: null }
    });
  });

  it("responds to Slack URL verification", async () => {
    const url = await listen({
      httpMode: true,
      port: 0,
      signingSecret: "test-secret",
      socketMode: false,
      watApiBaseUrl: "http://web:3000"
    });
    const body = JSON.stringify({ challenge: "abc123", type: "url_verification" });

    const response = await fetch(new URL("/slack/events", url), {
      body,
      headers: signSlackBody(body, "test-secret"),
      method: "POST"
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ challenge: "abc123" });
  });

  it("redirects Slack installs to OAuth authorize", async () => {
    const url = await listen({
      clientId: "client-id",
      clientSecret: "client-secret",
      httpMode: true,
      port: 0,
      redirectUri: "https://wat.example.com/slack/oauth/callback",
      signingSecret: "test-secret",
      socketMode: false,
      stateSecret: "state-secret",
      tokenEncryptionKey: "enc-key",
      watApiBaseUrl: "http://web:3000",
      watTeamId: "team_wat"
    });

    const response = await fetch(new URL("/slack/install", url), { redirect: "manual" });
    const location = new URL(response.headers.get("location")!);

    expect(response.status).toBe(302);
    expect(location.origin).toBe("https://slack.com");
    expect(location.pathname).toBe("/oauth/v2/authorize");
    expect(location.searchParams.get("client_id")).toBe("client-id");
    expect(location.searchParams.get("scope")).toBe(
      "commands,chat:write,app_mentions:read,users:read.email"
    );
    expect(location.searchParams.get("user_scope")).toBe("identity.basic,identity.email");
  });

  it("stores Slack OAuth callback installs with encrypted tokens", async () => {
    const store = new MemorySlackInstallStore();
    const fetchOAuth: typeof fetch = async () =>
      new Response(
        JSON.stringify({
          access_token: "xoxb-token",
          app_id: "A_WAT",
          authed_user: {
            access_token: "xoxp-token",
            id: "U_INSTALLER",
            scope: "identity.basic,identity.email",
            token_type: "user"
          },
          bot_user_id: "U_BOT",
          ok: true,
          scope: "commands,chat:write",
          team: { id: "T_WAT", name: "Wat Workspace" }
        })
      );
    const now = 1_700_000_000_000;
    const url = await listen(
      {
        clientId: "client-id",
        clientSecret: "client-secret",
        httpMode: true,
        port: 0,
        signingSecret: "test-secret",
        slackTeamWatTeamMap: { T_WAT: "team_wat" },
        socketMode: false,
        stateSecret: "state-secret",
        tokenEncryptionKey: "enc-key",
        watApiBaseUrl: "http://web:3000"
      },
      { fetchOAuth, installStore: store, now: () => now }
    );
    const state = createSlackOAuthState("state-secret", now, "nonce");

    const response = await fetch(new URL(`/slack/oauth/callback?code=abc&state=${state}`, url));
    const install = await store.getBySlackTeamId("T_WAT");

    expect(response.status).toBe(200);
    expect(install).toMatchObject({
      appId: "A_WAT",
      botScopes: ["commands", "chat:write"],
      installerSlackUserId: "U_INSTALLER",
      slackTeamId: "T_WAT",
      watTeamId: "team_wat"
    });
    expect(decryptToken(install!.botToken, "enc-key")).toBe("xoxb-token");
    expect(install!.userToken ? decryptToken(install!.userToken, "enc-key") : null).toBe(
      "xoxp-token"
    );
  });

  it("deletes installs on Slack uninstall events", async () => {
    const store = new MemorySlackInstallStore();
    await store.upsert({
      appId: "A_WAT",
      botScopes: ["commands"],
      botToken: encryptToken("xoxb-token", "enc-key"),
      botUserId: "U_BOT",
      installedAt: "2026-06-25T00:00:00.000Z",
      installerSlackUserId: "U_INSTALLER",
      slackTeamId: "T_WAT",
      updatedAt: "2026-06-25T00:00:00.000Z",
      userScopes: [],
      watTeamId: "team_wat"
    });
    const url = await listen(
      {
        httpMode: true,
        port: 0,
        signingSecret: "test-secret",
        socketMode: false,
        watApiBaseUrl: "http://web:3000"
      },
      { installStore: store }
    );
    const body = JSON.stringify({
      api_app_id: "A_WAT",
      event: { type: "app_uninstalled" },
      team_id: "T_WAT",
      type: "event_callback"
    });

    const response = await fetch(new URL("/slack/events", url), {
      body,
      headers: signSlackBody(body, "test-secret"),
      method: "POST"
    });

    expect(response.status).toBe(202);
    expect(await store.getBySlackTeamId("T_WAT")).toBeNull();
  });

  it("protects and renders metrics", async () => {
    const monitor = new InMemorySlackMonitor();
    monitor.increment("slack_event_total", { type: "app_uninstalled" });
    const url = await listen(
      {
        httpMode: true,
        metricsToken: "metrics-secret",
        port: 0,
        signingSecret: "test-secret",
        socketMode: false,
        watApiBaseUrl: "http://web:3000"
      },
      { monitor }
    );

    const unauthorized = await fetch(new URL("/metrics", url));
    const authorized = await fetch(new URL("/metrics", url), {
      headers: { authorization: "Bearer metrics-secret" }
    });

    expect(unauthorized.status).toBe(401);
    expect(authorized.status).toBe(200);
    expect(await authorized.text()).toContain('slack_event_total{type="app_uninstalled"} 1');
  });

  it("rejects unsigned Slack event requests", async () => {
    const url = await listen({
      httpMode: true,
      port: 0,
      signingSecret: "test-secret",
      socketMode: false,
      watApiBaseUrl: "http://web:3000"
    });

    const response = await fetch(new URL("/slack/events", url), {
      body: JSON.stringify({ event: {}, type: "event_callback" }),
      method: "POST"
    });

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "invalid_slack_signature" });
  });

  it("rejects replayed Slack event requests", async () => {
    const url = await listen({
      httpMode: true,
      port: 0,
      signingSecret: "test-secret",
      socketMode: false,
      watApiBaseUrl: "http://web:3000"
    });
    const body = JSON.stringify({ event: {}, type: "event_callback" });
    const staleTimestamp = `${Math.floor(Date.now() / 1000) - 301}`;

    const response = await fetch(new URL("/slack/events", url), {
      body,
      headers: signSlackBody(body, "test-secret", staleTimestamp),
      method: "POST"
    });

    expect(response.status).toBe(401);
  });

  it("requires an app token when socket mode is enabled", () => {
    expect(() =>
      validateConfig({
        httpMode: true,
        port: 3001,
        socketMode: true,
        watApiBaseUrl: "http://web:3000"
      })
    ).toThrow("SLACK_APP_TOKEN is required");
  });

  it("requires a bot token when socket mode is enabled", () => {
    expect(() =>
      validateConfig({
        appToken: "xapp-test",
        httpMode: true,
        port: 3001,
        signingSecret: "signing-secret",
        socketMode: true,
        watApiBaseUrl: "http://web:3000"
      })
    ).toThrow("SLACK_BOT_TOKEN is required");
  });

  it("requires a signing secret when HTTP mode is enabled", () => {
    expect(() =>
      validateConfig({
        httpMode: true,
        port: 3001,
        socketMode: false,
        watApiBaseUrl: "http://web:3000"
      })
    ).toThrow("SLACK_SIGNING_SECRET is required");
  });

  it("reads runtime config from env", () => {
    expect(
      configFromEnv({
        PORT: "4000",
        SLACK_APP_TOKEN: "xapp-test",
        SLACK_ADMIN_USER_IDS: "U_ADMIN, U_OWNER",
        SLACK_BOT_TOKEN: "xoxb-test",
        SLACK_CLIENT_ID: "client-id",
        SLACK_CLIENT_SECRET: "client-secret",
        SLACK_DATABASE_URL: "postgres://wat:wat@localhost:5432/wat",
        SLACK_INSTALL_STORE: "postgres",
        SLACK_INSTALL_STORE_PATH: ".wat-slack-installs.test.json",
        SLACK_REDIRECT_URI: "https://wat.example.com/slack/oauth/callback",
        SLACK_SIGNING_SECRET: "signing-secret",
        SLACK_SOCKET_MODE: "true",
        SLACK_STATE_SECRET: "state-secret",
        SLACK_TOKEN_ENCRYPTION_KEY: "enc-key",
        WAT_SLACK_TEAM_MAP: "T_WAT:team_wat",
        WAT_API_KEY: "wat-team-key",
        WAT_TEAM_ID: "wat-team-123",
        WAT_API_BASE_URL: "http://web:3000"
      })
    ).toMatchObject({
      appToken: "xapp-test",
      botToken: "xoxb-test",
      clientId: "client-id",
      clientSecret: "client-secret",
      databaseUrl: "postgres://wat:wat@localhost:5432/wat",
      installStore: "postgres",
      installStorePath: ".wat-slack-installs.test.json",
      port: 4000,
      redirectUri: "https://wat.example.com/slack/oauth/callback",
      signingSecret: "signing-secret",
      slackAdminUserIds: ["U_ADMIN", "U_OWNER"],
      slackTeamWatTeamMap: { T_WAT: "team_wat" },
      socketMode: true,
      stateSecret: "state-secret",
      tokenEncryptionKey: "enc-key",
      watApiKey: "wat-team-key",
      watApiBaseUrl: "http://web:3000",
      watTeamId: "wat-team-123"
    });
  });
});

function signSlackBody(
  body: string,
  secret: string,
  timestamp = `${Math.floor(Date.now() / 1000)}`
): Record<string, string> {
  const digest = createHmac("sha256", secret)
    .update(`v0:${timestamp}:${body}`, "utf8")
    .digest("hex");
  return {
    "content-type": "application/json",
    "x-slack-request-timestamp": timestamp,
    "x-slack-signature": `v0=${digest}`
  };
}

async function listen(
  config: Parameters<typeof createSlackHttpHandler>[0],
  deps?: Parameters<typeof createSlackHttpHandler>[1]
): Promise<URL> {
  const server = createServer(createSlackHttpHandler(config, deps));
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("server address unavailable");
  return new URL(`http://127.0.0.1:${address.port}`);
}
