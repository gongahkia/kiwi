import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { afterEach, describe, expect, it } from "vitest";

const root = new URL("../../..", import.meta.url);
const transports: StdioClientTransport[] = [];
const clientEnv = {
  ...process.env,
  WAT_API_KEY: "test-key",
  WAT_TEAM_DOMAINS: "example.com",
  WAT_TEAM_ID: "team_example"
} as Record<string, string>;

async function connectClient(): Promise<Client> {
  const transport = new StdioClientTransport({
    args: ["apps/mcp/dist/index.js"],
    command: process.execPath,
    cwd: root.pathname,
    env: clientEnv,
    stderr: "pipe"
  });
  transports.push(transport);

  const client = new Client({ name: "wat-mcp-test", version: "0.0.0" });
  await client.connect(transport);

  return client;
}

afterEach(async () => {
  await Promise.allSettled(transports.splice(0).map((transport) => transport.close()));
});

describe("wat mcp server", () => {
  it("lists the lookup and team tools over stdio", async () => {
    const client = await connectClient();
    const tools = await client.listTools();

    expect(tools.tools.map((tool) => tool.name).sort()).toEqual(["list_team_acronyms", "lookup"]);
  });

  it("returns typed lookup results with citations", async () => {
    const client = await connectClient();
    const result = await client.callTool({
      arguments: { api_key: "test-key", limit: 2, term: "CAP" },
      name: "lookup"
    });

    expect(result.isError).not.toBe(true);
    expect(result.structuredContent).toEqual({
      matches: expect.arrayContaining([
        expect.objectContaining({
          citations: expect.arrayContaining([expect.objectContaining({ url: expect.any(String) })]),
          expansion: expect.any(String),
          term: "CAP"
        })
      ]),
      team_id: "team_example"
    });
  });

  it("returns a paged team acronym list scoped by domain", async () => {
    const client = await connectClient();
    const result = await client.callTool({
      arguments: { api_key: "test-key", domain: "example.com", limit: 1 },
      name: "list_team_acronyms"
    });

    expect(result.isError).not.toBe(true);
    expect(result.structuredContent).toMatchObject({
      entries: [
        {
          entry_id: "team-example-cap",
          layer: "team",
          term: "CAP"
        }
      ],
      next_cursor: 1,
      team_id: "team_example"
    });
  });

  it("rejects calls without a valid api key", async () => {
    const client = await connectClient();
    const missing = await client.callTool({
      arguments: { term: "CAP" },
      name: "lookup"
    });
    const wrong = await client.callTool({
      arguments: { api_key: "wrong", term: "CAP" },
      name: "lookup"
    });
    const outOfScope = await client.callTool({
      arguments: { api_key: "test-key", domain: "invalid.example", limit: 1 },
      name: "list_team_acronyms"
    });
    const content = missing.content as Array<{ text: string; type: string }>;

    expect(missing.isError).toBe(true);
    expect(wrong.isError).toBe(true);
    expect(outOfScope.isError).toBe(true);
    expect(content[0]).toMatchObject({
      text: expect.stringContaining("api_key"),
      type: "text"
    });
  });
});
