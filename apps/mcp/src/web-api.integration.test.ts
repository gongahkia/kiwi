import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { GET as alternativesGET } from "../../web/src/app/api/v1/alternatives/route.js";
import { GET as searchGET } from "../../web/src/app/api/v1/search/route.js";
import { postApiSuggestion } from "../../web/src/app/api/v1/suggestions/handler.js";
import { GET as teamEntriesGET } from "../../web/src/app/api/v1/team/entries/route.js";
import { resetApiKeysForTest, seedApiKeyForTest } from "../../web/src/lib/api-keys.js";
import { resetSuggestionRateLimitForTest } from "../../web/src/lib/suggestion-rate-limit.js";
import {
  replaceTeamEntriesForTest,
  resetTeamEntriesForTest,
  type TeamEntry
} from "../../web/src/lib/team-entries.js";

const root = new URL("../../..", import.meta.url);
const transports: StdioClientTransport[] = [];
const servers: Server[] = [];
const teamId = "team_mcp";
const apiKey = "mcp-test-key";

const capEntry: TeamEntry = {
  contemporaries: ["MCP peer"],
  domains: ["platform"],
  expansion: "Change Approval Process",
  id: "team-mcp-cap",
  meaning: "Production change review fixture used by MCP integration tests.",
  sources: [
    {
      license: "proprietary-team",
      publisher: "wat mcp fixture",
      retrieved_at: "2026-07-10T00:00:00.000Z",
      snippet: "CAP is the production change review.",
      title: "MCP team glossary",
      url: "https://example.test/mcp/cap"
    }
  ],
  term: "CAP"
};

const peerEntry: TeamEntry = {
  contemporaries: ["CAP"],
  domains: ["platform"],
  expansion: "MCP Peer",
  id: "team-mcp-peer",
  meaning: "Related MCP integration fixture.",
  sources: [
    {
      license: "proprietary-team",
      publisher: "wat mcp fixture",
      retrieved_at: "2026-07-10T00:00:00.000Z",
      snippet: "MCP peer is an alternative fixture.",
      title: "MCP team glossary",
      url: "https://example.test/mcp/peer"
    }
  ],
  term: "MCP peer"
};

async function body(request: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of request)
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  return Buffer.concat(chunks).toString("utf8");
}

function headers(request: IncomingMessage): Headers {
  const result = new Headers();
  for (const [key, value] of Object.entries(request.headers)) {
    if (Array.isArray(value)) {
      for (const item of value) result.append(key, item);
    } else if (value != null) {
      result.set(key, value);
    }
  }
  return result;
}

async function writeResponse(response: ServerResponse, nextResponse: Response): Promise<void> {
  response.writeHead(nextResponse.status, Object.fromEntries(nextResponse.headers.entries()));
  response.end(Buffer.from(await nextResponse.arrayBuffer()));
}

async function startWebApiServer(): Promise<string> {
  const server = createServer(async (request, response) => {
    const origin = `http://${request.headers.host ?? "127.0.0.1"}`;
    const url = new URL(request.url ?? "/", origin);
    const init: RequestInit = { headers: headers(request), method: request.method };
    if (request.method !== "GET" && request.method !== "HEAD") init.body = await body(request);
    const nextRequest = new NextRequest(url, init);

    if (request.method === "GET" && url.pathname === "/api/v1/search") {
      await writeResponse(response, await searchGET(nextRequest));
      return;
    }
    if (request.method === "GET" && url.pathname === "/api/v1/team/entries") {
      await writeResponse(response, await teamEntriesGET(nextRequest));
      return;
    }
    if (request.method === "GET" && url.pathname === "/api/v1/alternatives") {
      await writeResponse(response, await alternativesGET(nextRequest));
      return;
    }
    if (request.method === "POST" && url.pathname === "/api/v1/suggestions") {
      await writeResponse(
        response,
        await postApiSuggestion(nextRequest, {
          createSuggestion: async ({ actorId, suggestion, teamId: scopedTeamId }) => ({
            actor_id: actorId,
            after_jsonb: suggestion,
            before_jsonb: null,
            created_at: "2026-07-10T00:00:00.000Z",
            id: "suggestion_mcp",
            status: "pending",
            target_id: null,
            target_type: "entry",
            team_id: scopedTeamId
          })
        })
      );
      return;
    }
    response.writeHead(404, { "content-type": "application/json" });
    response.end(JSON.stringify({ error: "not_found" }));
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  servers.push(server);
  const address = server.address() as AddressInfo;
  return `http://127.0.0.1:${address.port}`;
}

async function connectClient(apiBase: string): Promise<Client> {
  const transport = new StdioClientTransport({
    args: ["apps/mcp/dist/index.js"],
    command: process.execPath,
    cwd: root.pathname,
    env: {
      ...process.env,
      WAT_API_BASE_URL: apiBase,
      WAT_API_KEY: apiKey
    } as Record<string, string>,
    stderr: "pipe"
  });
  transports.push(transport);
  const client = new Client({ name: "wat-mcp-web-api-test", version: "0.0.0" });
  await client.connect(transport);
  return client;
}

afterEach(async () => {
  await Promise.allSettled(transports.splice(0).map((transport) => transport.close()));
  await Promise.allSettled(
    servers.splice(0).map((server) => new Promise<void>((resolve) => server.close(() => resolve())))
  );
  resetApiKeysForTest();
  resetSuggestionRateLimitForTest();
  resetTeamEntriesForTest(teamId);
});

describe("wat mcp against web API handlers", () => {
  it("runs lookup, list, alternatives, and suggest against seeded web fixtures", async () => {
    seedApiKeyForTest({ key: apiKey, scopes: ["search", "suggest"], teamId });
    replaceTeamEntriesForTest([capEntry, peerEntry], teamId);
    const client = await connectClient(await startWebApiServer());

    const lookup = await client.callTool({ arguments: { term: "CAP" }, name: "lookup" });
    const list = await client.callTool({
      arguments: { domain: "platform", limit: 10 },
      name: "list_team_acronyms"
    });
    const alternatives = await client.callTool({
      arguments: { term: "CAP" },
      name: "list_alternatives"
    });
    const suggestion = await client.callTool({
      arguments: {
        domains: ["platform"],
        expansion: "Model Context Protocol",
        meaning: "Protocol used by local model tools.",
        source_title: "MCP docs",
        source_url: "https://example.test/mcp/docs",
        term: "MCP"
      },
      name: "suggest_definition"
    });

    expect(lookup.isError).not.toBe(true);
    expect(lookup.structuredContent).toMatchObject({
      matches: expect.arrayContaining([
        expect.objectContaining({ entry_id: "team-mcp-cap", layer: "team", term: "CAP" })
      ]),
      team_id: teamId
    });
    expect(list.isError).not.toBe(true);
    expect(list.structuredContent).toMatchObject({
      entries: [
        { entry_id: "team-mcp-cap", term: "CAP" },
        { entry_id: "team-mcp-peer", term: "MCP peer" }
      ],
      next_cursor: null,
      team_id: teamId
    });
    expect(alternatives.isError).not.toBe(true);
    expect(alternatives.structuredContent).toMatchObject({
      alternatives: [{ entry_id: "team-mcp-peer", term: "MCP peer" }],
      entry: { entry_id: "team-mcp-cap", term: "CAP" },
      team_id: teamId
    });
    expect(suggestion.isError).not.toBe(true);
    expect(suggestion.structuredContent).toMatchObject({
      status: "pending",
      suggestion_id: "suggestion_mcp",
      team_id: teamId
    });
  });
});
