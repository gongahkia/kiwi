import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "node:http";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(appRoot, "../..");

const source = {
  license: "proprietary-team",
  publisher: "wat contract",
  retrieved_at: "2026-06-25T00:00:00.000Z",
  snippet: "CAP contract fixture.",
  source_quality: "community",
  title: "CAP contract",
  url: "https://example.com/cap"
};

function entry(term) {
  return {
    aliases: [],
    confidence_tier: "T4",
    contemporaries: [],
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

function result(term, entryId = `entry-${term.toLowerCase()}`) {
  return {
    citations: [source],
    confidence_tier: "T4",
    contemporaries: [],
    domains: ["example.com"],
    entry_id: entryId,
    expansion: `${term} expansion`,
    layer: "team",
    meaning: `${term} meaning`,
    score: 1,
    term
  };
}

function writeJson(response, status, body) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

const apiServer = createServer((request, response) => {
  const url = new URL(request.url ?? "/", "http://127.0.0.1");
  if (request.headers.authorization !== "Bearer test-key") {
    writeJson(response, 401, { error: "invalid_api_key" });
    return;
  }
  if (url.pathname === "/api/v1/search") {
    writeJson(response, 200, {
      matches: [{ entry: entry(url.searchParams.get("q") ?? "CAP"), score: 1 }],
      team_id: "team_example"
    });
    return;
  }
  if (url.pathname === "/api/v1/team/entries") {
    writeJson(response, 200, {
      entries: [result("CAP", "team-example-cap")],
      next_cursor: null,
      team_id: "team_example"
    });
    return;
  }
  writeJson(response, 404, { error: "not_found" });
});

await new Promise((resolve) => apiServer.listen(0, "127.0.0.1", resolve));
const apiAddress = apiServer.address();
const apiBaseUrl = `http://127.0.0.1:${apiAddress.port}`;

const transport = new StdioClientTransport({
  args: ["dist/index.js"],
  command: "node",
  cwd: appRoot,
  env: {
    ...process.env,
    WAT_API_KEY: "test-key",
    WAT_API_BASE_URL: apiBaseUrl
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
    arguments: { limit: 1, term: "CAP" },
    name: "lookup"
  });
  const lookupMatch = lookup.structuredContent?.matches?.[0];
  if (lookupMatch?.term !== "CAP" || lookupMatch?.citations?.[0]?.url == null) {
    throw new Error("lookup contract failed");
  }

  const list = await client.callTool({
    arguments: { domain: "example.com", limit: 1 },
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
  await new Promise((resolve) => apiServer.close(resolve));
}
