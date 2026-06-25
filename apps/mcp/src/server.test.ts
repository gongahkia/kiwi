import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it } from "vitest";

const root = new URL("../../..", import.meta.url);
const transports: StdioClientTransport[] = [];
const servers: Server[] = [];
const clientEnv = {
  ...process.env,
  WAT_API_KEY: "test-key"
} as Record<string, string>;

const source = {
  license: "proprietary-team",
  publisher: "wat test",
  retrieved_at: "2026-06-25T00:00:00.000Z",
  snippet: "CAP fixture.",
  source_quality: "community",
  title: "CAP fixture",
  url: "https://example.com/cap"
};

function watResult(term: string, entryId = `entry-${term.toLowerCase()}`) {
  return {
    citations: [source],
    confidence_tier: "T4",
    contemporaries: term === "CSR" ? ["SSR"] : [],
    domains: ["example.com"],
    entry_id: entryId,
    expansion: `${term} expansion`,
    layer: "team",
    meaning: `${term} meaning`,
    score: 1,
    term
  };
}

function searchEntry(term: string) {
  return {
    aliases: [],
    confidence_tier: "T4",
    contemporaries: term === "CSR" ? ["SSR"] : [],
    domains: ["example.com"],
    expansions: [`${term} expansion`],
    id: `entry-${term.toLowerCase()}`,
    layer: "team",
    meaning_short: `${term} meaning`,
    sources: [source],
    term,
    term_normalized: term.toLowerCase()
  };
}

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

async function startApiServer(
  handler?: (request: IncomingMessage, response: ServerResponse, url: URL) => boolean
): Promise<string> {
  const server = createServer((request, response) => {
    const url = new URL(request.url ?? "/", "http://127.0.0.1");
    if (handler?.(request, response, url)) return;
    if (request.headers.authorization !== "Bearer test-key") {
      writeJson(response, 401, { error: "invalid_api_key" });
      return;
    }
    if (url.pathname === "/api/v1/search") {
      writeJson(response, 200, {
        matches: [{ entry: searchEntry(url.searchParams.get("q") ?? "CAP"), score: 1 }],
        team_id: "team_example"
      });
      return;
    }
    if (url.pathname === "/api/v1/alternatives") {
      const term = url.searchParams.get("term") ?? "CSR";
      writeJson(response, 200, {
        alternatives: [watResult(term === "CSR" ? "SSR" : `${term} peer`)],
        entry: watResult(term),
        team_id: "team_example",
        unresolved_terms: []
      });
      return;
    }
    if (url.pathname === "/api/v1/team/entries") {
      writeJson(response, 200, {
        entries: [watResult("CAP", "team-example-cap")],
        next_cursor: 1,
        team_id: "team_example"
      });
      return;
    }
    if (url.pathname === "/api/v1/suggestions") {
      writeJson(response, 201, {
        suggestion: {
          created_at: "2026-06-25T00:00:00.000Z",
          id: "suggestion_123",
          status: "pending",
          team_id: "team_example"
        }
      });
      return;
    }
    writeJson(response, 404, { error: "not_found" });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  servers.push(server);
  const address = server.address() as AddressInfo;
  return `http://127.0.0.1:${address.port}`;
}

async function connectClient(env: Record<string, string> = {}): Promise<Client> {
  const transport = new StdioClientTransport({
    args: ["apps/mcp/dist/index.js"],
    command: process.execPath,
    cwd: root.pathname,
    env: { ...clientEnv, ...env },
    stderr: "pipe"
  });
  transports.push(transport);

  const client = new Client({ name: "wat-mcp-test", version: "0.0.0" });
  await client.connect(transport);
  return client;
}

afterEach(async () => {
  await Promise.allSettled(transports.splice(0).map((transport) => transport.close()));
  await Promise.allSettled(
    servers.splice(0).map((server) => new Promise<void>((resolve) => server.close(() => resolve())))
  );
});

describe("wat mcp server", () => {
  it("lists the lookup and team tools over stdio", async () => {
    const apiBase = await startApiServer();
    const client = await connectClient({ WAT_API_BASE_URL: apiBase });
    const tools = await client.listTools();

    expect(tools.tools.map((tool) => tool.name).sort()).toEqual([
      "list_alternatives",
      "list_team_acronyms",
      "lookup",
      "suggest_definition"
    ]);
    expect(tools.tools.find((tool) => tool.name === "lookup")?.inputSchema).not.toMatchObject({
      properties: { api_key: expect.anything() }
    });
  });

  it("returns typed lookup results with citations", async () => {
    const apiBase = await startApiServer();
    const client = await connectClient({ WAT_API_BASE_URL: apiBase });
    const result = await client.callTool({
      arguments: { limit: 2, term: "CAP" },
      name: "lookup"
    });

    expect(result.isError).not.toBe(true);
    expect(result.structuredContent).toEqual({
      matches: expect.arrayContaining([
        expect.objectContaining({
          citations: expect.arrayContaining([expect.objectContaining({ url: expect.any(String) })]),
          contemporaries: expect.any(Array),
          expansion: expect.any(String),
          term: "CAP"
        })
      ]),
      team_id: "team_example"
    });
  });

  it("returns resolved alternatives for a term", async () => {
    const apiBase = await startApiServer();
    const client = await connectClient({ WAT_API_BASE_URL: apiBase });
    const result = await client.callTool({
      arguments: { term: "CSR" },
      name: "list_alternatives"
    });

    expect(result.isError).not.toBe(true);
    expect(result.structuredContent).toMatchObject({
      alternatives: [{ term: "SSR" }],
      entry: { term: "CSR" },
      team_id: "team_example",
      unresolved_terms: []
    });
  });

  it("returns a paged team acronym list scoped by domain", async () => {
    const apiBase = await startApiServer();
    const client = await connectClient({ WAT_API_BASE_URL: apiBase });
    const result = await client.callTool({
      arguments: { domain: "example.com", limit: 1 },
      name: "list_team_acronyms"
    });

    expect(result.isError).not.toBe(true);
    expect(result.structuredContent).toMatchObject({
      entries: [{ entry_id: "team-example-cap", layer: "team", term: "CAP" }],
      next_cursor: 1,
      team_id: "team_example"
    });
  });

  it("fails when remote API config is missing or rejected", async () => {
    const missingConfigClient = await connectClient({ WAT_API_BASE_URL: "", WAT_API_KEY: "" });
    const missing = await missingConfigClient.callTool({
      arguments: { term: "CAP" },
      name: "lookup"
    });
    const apiBase = await startApiServer();
    const rejectedClient = await connectClient({
      WAT_API_BASE_URL: apiBase,
      WAT_API_KEY: "bad-key"
    });
    const rejected = await rejectedClient.callTool({
      arguments: { term: "CAP" },
      name: "lookup"
    });
    const content = missing.content as Array<{ text: string; type: string }>;

    expect(missing.isError).toBe(true);
    expect(rejected.isError).toBe(true);
    expect(content[0]).toMatchObject({
      text: expect.stringContaining("WAT_API_BASE_URL"),
      type: "text"
    });
  });

  it("surfaces remote suggestion policy failures", async () => {
    const apiBase = await startApiServer((_request, response, url) => {
      if (url.pathname !== "/api/v1/suggestions") return false;
      writeJson(response, 403, { error: "suggest_definition disabled by team policy" });
      return true;
    });
    const client = await connectClient({ WAT_API_BASE_URL: apiBase });
    const result = await client.callTool({
      arguments: {
        expansion: "Customer Availability Promise",
        meaning: "Team-specific availability target.",
        source_title: "Team glossary",
        source_url: "https://example.com/glossary/cap",
        term: "CAP"
      },
      name: "suggest_definition"
    });
    const content = result.content as Array<{ text: string; type: string }>;

    expect(result.isError).toBe(true);
    expect(content[0]).toMatchObject({
      text: expect.stringContaining("team policy"),
      type: "text"
    });
  });

  it("queues write suggestions through the remote API", async () => {
    const apiBase = await startApiServer();
    const client = await connectClient({ WAT_API_BASE_URL: apiBase });
    const result = await client.callTool({
      arguments: {
        domains: ["customer-success"],
        expansion: "Customer Availability Promise",
        meaning: "Team-specific availability target.",
        source_title: "Team glossary",
        source_url: "https://example.com/glossary/cap",
        term: "CAP"
      },
      name: "suggest_definition"
    });

    expect(result.isError).not.toBe(true);
    expect(result.structuredContent).toMatchObject({
      status: "pending",
      suggestion_id: "suggestion_123",
      team_id: "team_example"
    });
  });
});
