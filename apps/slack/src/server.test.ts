import { createHmac } from "node:crypto";
import { createServer } from "node:http";
import { afterEach, describe, expect, it } from "vitest";

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
        SLACK_SIGNING_SECRET: "signing-secret",
        SLACK_SOCKET_MODE: "true",
        WAT_API_KEY: "wat-team-key",
        WAT_TEAM_ID: "wat-team-123",
        WAT_API_BASE_URL: "http://web:3000"
      })
    ).toMatchObject({
      appToken: "xapp-test",
      port: 4000,
      signingSecret: "signing-secret",
      socketMode: true,
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

async function listen(config: Parameters<typeof createSlackHttpHandler>[0]): Promise<URL> {
  const server = createServer(createSlackHttpHandler(config));
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("server address unavailable");
  return new URL(`http://127.0.0.1:${address.port}`);
}
