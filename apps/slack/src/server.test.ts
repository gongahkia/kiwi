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
      socketMode: true,
      watApiBaseUrl: "http://web:3000"
    });

    const response = await fetch(new URL("/healthz", url));

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      mode: { http: "ok", socket: "ok" },
      service: "slack",
      status: "ok"
    });
  });

  it("responds to Slack URL verification", async () => {
    const url = await listen({
      httpMode: true,
      port: 0,
      socketMode: false,
      watApiBaseUrl: "http://web:3000"
    });

    const response = await fetch(new URL("/slack/events", url), {
      body: JSON.stringify({ challenge: "abc123", type: "url_verification" }),
      method: "POST"
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ challenge: "abc123" });
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

  it("reads runtime config from env", () => {
    expect(
      configFromEnv({
        PORT: "4000",
        SLACK_APP_TOKEN: "xapp-test",
        SLACK_SOCKET_MODE: "true",
        WAT_API_BASE_URL: "http://web:3000"
      })
    ).toMatchObject({
      appToken: "xapp-test",
      port: 4000,
      socketMode: true,
      watApiBaseUrl: "http://web:3000"
    });
  });
});

async function listen(config: Parameters<typeof createSlackHttpHandler>[0]): Promise<URL> {
  const server = createServer(createSlackHttpHandler(config));
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("server address unavailable");
  return new URL(`http://127.0.0.1:${address.port}`);
}
