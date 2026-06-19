#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { createWatMcpServer } from "./server.js";

const server = createWatMcpServer();
const transport = new StdioServerTransport();

await server.connect(transport);
