import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { randomUUID } from "node:crypto";

import { createWatMcpServer } from "./server.js";

const defaultHost = "127.0.0.1";
const defaultPath = "/mcp";
const defaultPort = 8787;
const corsHeaders = {
  "access-control-allow-headers":
    "accept, authorization, content-type, last-event-id, mcp-protocol-version, mcp-session-id",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS"
};

export interface WatMcpHttpConfig {
  allowedOrigins: string[];
  env: Record<string, string | undefined>;
  host: string;
  path: string;
  port: number;
  token?: string;
}

export interface WatMcpHttpRuntime {
  close: () => Promise<void>;
  config: WatMcpHttpConfig;
  server: Server;
  url: string;
}

export interface WatMcpHttpOptions {
  allowedOrigins?: string[];
  env?: Record<string, string | undefined>;
  host?: string;
  path?: string;
  port?: number;
  token?: string;
}

export function httpConfigFromEnv(
  env: Record<string, string | undefined> = process.env
): WatMcpHttpConfig {
  return resolveHttpConfig({
    allowedOrigins: csv(env.WAT_MCP_ALLOWED_ORIGINS),
    env,
    host: env.WAT_MCP_HOST,
    path: env.WAT_MCP_PATH,
    port: env.WAT_MCP_PORT ? Number(env.WAT_MCP_PORT) : undefined,
    token: env.WAT_MCP_HTTP_TOKEN
  });
}

export function resolveHttpConfig(options: WatMcpHttpOptions = {}): WatMcpHttpConfig {
  const env = options.env ?? process.env;
  const host = options.host?.trim() || defaultHost;
  const path = normalizePath(options.path?.trim() || defaultPath);
  const port = options.port ?? defaultPort;
  const token = options.token?.trim() || undefined;
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error("invalid MCP HTTP port");
  if (!isLoopbackHost(host) && !token) {
    throw new Error("WAT_MCP_HTTP_TOKEN is required when WAT_MCP_HOST is not loopback");
  }
  return {
    allowedOrigins: options.allowedOrigins ?? csv(env.WAT_MCP_ALLOWED_ORIGINS),
    env,
    host,
    path,
    port,
    token
  };
}

export async function startWatMcpHttpServer(
  options: WatMcpHttpOptions = {}
): Promise<WatMcpHttpRuntime> {
  const config = resolveHttpConfig(options);
  const sessions = new Map<string, StreamableHTTPServerTransport>();

  const server = createServer(async (request, response) => {
    await handleHttpRequest(config, sessions, request, response);
  });
  await new Promise<void>((resolve) => server.listen(config.port, config.host, resolve));
  const address = server.address() as AddressInfo;
  const host = isWildcardHost(config.host) ? defaultHost : config.host;
  return {
    close: async () => {
      await Promise.allSettled(Array.from(sessions.values()).map((transport) => transport.close()));
      sessions.clear();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
    config: { ...config, port: address.port },
    server,
    url: `http://${host}:${address.port}`
  };
}

async function handleHttpRequest(
  config: WatMcpHttpConfig,
  sessions: Map<string, StreamableHTTPServerTransport>,
  request: IncomingMessage,
  response: ServerResponse
): Promise<void> {
  const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "127.0.0.1"}`);
  if (url.pathname === "/healthz") {
    writeJson(response, 200, { service: "wat-mcp", status: "ok", transport: "streamable-http" });
    return;
  }
  if (url.pathname !== config.path) {
    writeJson(response, 404, { error: "not_found" });
    return;
  }
  if (!originAllowed(request.headers.origin, config)) {
    writeJson(response, 403, { error: "origin_not_allowed" });
    return;
  }
  applyCorsHeaders(response, request.headers.origin, config);
  if (request.method === "OPTIONS") {
    response.writeHead(204);
    response.end();
    return;
  }
  if (config.token && request.headers.authorization !== `Bearer ${config.token}`) {
    writeJson(response, 401, { error: "unauthorized" });
    return;
  }
  if (!["DELETE", "GET", "POST"].includes(request.method ?? "")) {
    writeJson(response, 405, { error: "method_not_allowed" });
    return;
  }
  const sessionId = headerValue(request.headers["mcp-session-id"]);
  let transport = sessionId ? sessions.get(sessionId) : undefined;
  if (sessionId && !transport) {
    writeJson(response, 404, { error: "session_not_found" });
    return;
  }
  if (!transport) transport = await createMcpTransport(config, sessions);
  try {
    await transport.handleRequest(request, response);
  } catch (error) {
    if (!response.headersSent) writeJson(response, 500, { error: "mcp_transport_failed" });
    else response.destroy(error instanceof Error ? error : new Error(String(error)));
  } finally {
    if (!transport.sessionId) await transport.close();
  }
}

async function createMcpTransport(
  config: WatMcpHttpConfig,
  sessions: Map<string, StreamableHTTPServerTransport>
): Promise<StreamableHTTPServerTransport> {
  let transport: StreamableHTTPServerTransport;
  transport = new StreamableHTTPServerTransport({
    enableJsonResponse: true,
    onsessioninitialized: (sessionId) => {
      sessions.set(sessionId, transport);
    },
    sessionIdGenerator: randomUUID
  });
  transport.onclose = () => {
    if (transport.sessionId) sessions.delete(transport.sessionId);
  };
  await createWatMcpServer({ env: config.env }).connect(transport);
  return transport;
}

function applyCorsHeaders(
  response: ServerResponse,
  origin: string | undefined,
  config: WatMcpHttpConfig
): void {
  for (const [key, value] of Object.entries(corsHeaders)) response.setHeader(key, value);
  response.setHeader("vary", "Origin");
  if (origin && originAllowed(origin, config))
    response.setHeader("access-control-allow-origin", origin);
}

function originAllowed(origin: string | undefined, config: WatMcpHttpConfig): boolean {
  if (!origin) return true;
  if (config.allowedOrigins.includes(origin)) return true;
  try {
    return isLoopbackHost(new URL(origin).hostname);
  } catch {
    return false;
  }
}

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

function headerValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function csv(value: string | undefined): string[] {
  return (value ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function normalizePath(value: string): string {
  const path = value.startsWith("/") ? value : `/${value}`;
  return path.replace(/\/+$/, "") || defaultPath;
}

function isLoopbackHost(host: string): boolean {
  return ["127.0.0.1", "::1", "localhost"].includes(host);
}

function isWildcardHost(host: string): boolean {
  return ["0.0.0.0", "::"].includes(host);
}
