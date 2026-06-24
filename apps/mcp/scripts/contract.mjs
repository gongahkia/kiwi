import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(appRoot, "../..");

const transport = new StdioClientTransport({
  args: ["dist/index.js"],
  command: "node",
  cwd: appRoot,
  env: {
    ...process.env,
    WAT_API_KEY: "test-key",
    WAT_TEAM_DOMAINS: "example.com",
    WAT_TEAM_ID: "team_example"
  },
  stderr: "pipe"
});

const client = new Client({
  name: "wat-contract",
  version: "0.0.0"
});

await client.connect(transport);

try {
  const tools = await client.listTools();
  const toolNames = tools.tools.map((tool) => tool.name).sort();
  for (const expected of ["list_team_acronyms", "lookup"]) {
    if (!toolNames.includes(expected)) {
      throw new Error(`missing MCP tool: ${expected}`);
    }
  }

  const lookup = await client.callTool({
    arguments: { api_key: "test-key", limit: 1, term: "CAP" },
    name: "lookup"
  });
  const lookupMatch = lookup.structuredContent?.matches?.[0];
  if (lookupMatch?.term !== "CAP" || lookupMatch?.citations?.[0]?.url == null) {
    throw new Error("lookup contract failed");
  }

  const list = await client.callTool({
    arguments: { api_key: "test-key", domain: "example.com", limit: 1 },
    name: "list_team_acronyms"
  });
  const teamEntry = list.structuredContent?.entries?.[0];
  if (
    teamEntry?.entry_id !== "team-example-cap" ||
    list.structuredContent?.team_id !== "team_example"
  ) {
    throw new Error("list_team_acronyms contract failed");
  }

  console.log(`mcp contract ok: ${repoRoot}`);
} finally {
  await client.close();
}
