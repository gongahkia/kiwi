import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { createServer, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it } from "vitest";

import { resolveHttpConfig, startWatMcpHttpServer, type WatMcpHttpRuntime } from "./http.js";

const runtimes: WatMcpHttpRuntime[] = [];
const apiServers: Server[] = [];

const source = {
  license: "proprietary-team",
  publisher: "wat remote mcp test",
  retrieved_at: "2026-07-10T00:00:00.000Z",
  snippet: "CAP fixture.",
  source_quality: "community",
  title: "CAP fixture",
  url: "https://example.test/cap"
};

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

async function startApiServer(): Promise<string> {
  const server = createServer((request, response) => {
    const url = new URL(request.url ?? "/", "http://127.0.0.1");
    if (request.headers.authorization !== "Bearer team-key") {
      writeJson(response, 401, { error: "invalid_api_key" });
      return;
    }
    if (url.pathname === "/api/v1/search") {
      writeJson(response, 200, {
        matches: [
          {
            entry: {
              aliases: [],
              confidence_tier: "T4",
              contemporaries: [],
              domains: ["platform"],
              expansions: ["Change Approval Process"],
              id: "team-cap",
              layer: "team",
              meaning_short: "Production change review.",
              sources: [source],
              term: url.searchParams.get("q") ?? "CAP",
              term_normalized: "cap"
            },
            score: 1
          }
        ],
        team_id: "team_remote"
      });
      return;
    }
    writeJson(response, 404, { error: "not_found" });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  apiServers.push(server);
  const address = server.address() as AddressInfo;
  return `http://127.0.0.1:${address.port}`;
}

afterEach(async () => {
  await Promise.allSettled(runtimes.splice(0).map((runtime) => runtime.close()));
  await Promise.allSettled(
    apiServers
      .splice(0)
      .map((server) => new Promise<void>((resolve) => server.close(() => resolve())))
  );
});

describe("wat MCP HTTP transport", () => {
  it("defaults to loopback and requires a token for public binds", () => {
    expect(resolveHttpConfig({ env: {}, port: 0 })).toMatchObject({
      host: "127.0.0.1",
      path: "/mcp",
      port: 0
    });
    expect(() => resolveHttpConfig({ env: {}, host: "0.0.0.0", port: 8787 })).toThrow(
      /WAT_MCP_HTTP_TOKEN/
    );
    expect(
      resolveHttpConfig({
        env: {},
        host: "0.0.0.0",
        path: "custom-mcp",
        port: 8787,
        token: "remote-token"
      })
    ).toMatchObject({ host: "0.0.0.0", path: "/custom-mcp", token: "remote-token" });
  });

  it("serves health and rejects unknown origins before MCP handling", async () => {
    const runtime = await startWatMcpHttpServer({
      env: { WAT_API_BASE_URL: "http://127.0.0.1:1", WAT_API_KEY: "team-key" },
      port: 0,
      token: "remote-token"
    });
    runtimes.push(runtime);

    await expect(
      fetch(`${runtime.url}/healthz`).then((response) => response.json())
    ).resolves.toEqual({ service: "wat-mcp", status: "ok", transport: "streamable-http" });
    await expect(
      fetch(`${runtime.url}/mcp`, {
        headers: { origin: "https://evil.example" },
        method: "OPTIONS"
      }).then((response) => response.status)
    ).resolves.toBe(403);
  });

  it("runs lookup over Streamable HTTP with endpoint bearer auth", async () => {
    const apiBase = await startApiServer();
    const runtime = await startWatMcpHttpServer({
      env: { WAT_API_BASE_URL: apiBase, WAT_API_KEY: "team-key" },
      port: 0,
      token: "remote-token"
    });
    runtimes.push(runtime);

    const unauthorized = await fetch(`${runtime.url}/mcp`, {
      body: JSON.stringify({ id: 1, jsonrpc: "2.0", method: "initialize", params: {} }),
      headers: {
        accept: "application/json, text/event-stream",
        "content-type": "application/json"
      },
      method: "POST"
    });
    expect(unauthorized.status).toBe(401);

    const transport = new StreamableHTTPClientTransport(new URL(`${runtime.url}/mcp`), {
      requestInit: { headers: { authorization: "Bearer remote-token" } }
    });
    const client = new Client({ name: "wat-mcp-http-test", version: "0.0.0" });
    await client.connect(transport);
    const result = await client.callTool({ arguments: { term: "CAP" }, name: "lookup" });

    expect(result.isError).not.toBe(true);
    expect(result.structuredContent).toMatchObject({
      matches: [{ entry_id: "team-cap", layer: "team", term: "CAP" }],
      team_id: "team_remote"
    });
    await transport.close();
  });
});
