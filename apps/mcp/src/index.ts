#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { startWatMcpHttpServer } from "./http.js";
import { createWatMcpServer } from "./server.js";

const args = new Set(process.argv.slice(2));

if (args.has("--http") || process.env.WAT_MCP_TRANSPORT === "http") {
  const runtime = await startWatMcpHttpServer();
  console.error(`wat MCP HTTP listening on ${runtime.url}${runtime.config.path}`);
  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.once(signal, () => {
      runtime.close().finally(() => process.exit(0));
    });
  }
} else {
  const server = createWatMcpServer();
  const transport = new StdioServerTransport();

  await server.connect(transport);
}
