import { createHmac, timingSafeEqual } from "node:crypto";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";

export interface SlackRuntimeConfig {
  appToken?: string;
  httpMode: boolean;
  port: number;
  signingSecret?: string;
  socketMode: boolean;
  watApiKey?: string;
  watApiBaseUrl: string;
  watTeamId?: string;
}

export function configFromEnv(env: NodeJS.ProcessEnv = process.env): SlackRuntimeConfig {
  return {
    appToken: env.SLACK_APP_TOKEN,
    httpMode: env.SLACK_HTTP_MODE !== "false",
    port: Number(env.PORT ?? 3001),
    signingSecret: env.SLACK_SIGNING_SECRET,
    socketMode: env.SLACK_SOCKET_MODE === "true",
    watApiKey: env.WAT_API_KEY,
    watApiBaseUrl: env.WAT_API_BASE_URL ?? "http://localhost:3000",
    watTeamId: env.WAT_TEAM_ID
  };
}

export function validateConfig(config: SlackRuntimeConfig): void {
  if (!Number.isFinite(config.port) || config.port < 1) {
    throw new Error("PORT must be a positive number");
  }
  if (config.socketMode && !config.appToken) {
    throw new Error("SLACK_APP_TOKEN is required when SLACK_SOCKET_MODE=true");
  }
  if (config.httpMode && !config.signingSecret) {
    throw new Error("SLACK_SIGNING_SECRET is required when Slack HTTP mode is enabled");
  }
}

export function createSlackHttpHandler(config: SlackRuntimeConfig) {
  return async (request: IncomingMessage, response: ServerResponse) => {
    if (request.method === "GET" && request.url === "/healthz") {
      writeJson(response, 200, {
        mode: {
          http: config.httpMode ? "ok" : "disabled",
          socket: config.socketMode ? "ok" : "disabled"
        },
        service: "slack",
        status: "ok",
        wat_api_auth: {
          key: config.watApiKey ? "configured" : "missing",
          team_id: config.watTeamId ?? null
        },
        wat_api_base_url: config.watApiBaseUrl
      });
      return;
    }

    if (request.method === "POST" && request.url === "/slack/events") {
      const rawBody = await readRawBody(request);
      if (!verifySlackRequest(config, request, rawBody)) {
        writeJson(response, 401, { error: "invalid_slack_signature" });
        return;
      }

      const payload = parseJsonBody(rawBody);
      if (payload?.type === "url_verification" && typeof payload.challenge === "string") {
        writeJson(response, 200, { challenge: payload.challenge });
        return;
      }

      writeJson(response, 202, { ok: true });
      return;
    }

    writeJson(response, 404, { error: "not_found" });
  };
}

export async function startSlackRuntime(config = configFromEnv()): Promise<void> {
  validateConfig(config);
  if (config.socketMode) startSocketModeLoop();

  if (!config.httpMode) {
    await new Promise(() => undefined);
    return;
  }

  const server = createServer(createSlackHttpHandler(config));
  await new Promise<void>((resolve) => server.listen(config.port, "0.0.0.0", resolve));
  console.log(
    JSON.stringify({
      event: "slack_started",
      http: true,
      port: config.port,
      socket: config.socketMode
    })
  );
}

function startSocketModeLoop(): void {
  setInterval(() => undefined, 30_000);
}

async function readRawBody(request: IncomingMessage): Promise<Buffer> {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

function parseJsonBody(rawBody: Buffer): Record<string, unknown> | null {
  if (rawBody.length === 0) return null;
  return JSON.parse(rawBody.toString("utf8")) as Record<string, unknown>;
}

function verifySlackRequest(
  config: SlackRuntimeConfig,
  request: IncomingMessage,
  rawBody: Buffer
): boolean {
  if (!config.signingSecret) return false;

  const timestamp = headerValue(request, "x-slack-request-timestamp");
  const signature = headerValue(request, "x-slack-signature");
  if (!timestamp || !signature) return false;

  const timestampSeconds = Number(timestamp);
  if (!Number.isInteger(timestampSeconds)) return false;

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - timestampSeconds) > 60 * 5) return false;

  const baseString = `v0:${timestamp}:${rawBody.toString("utf8")}`;
  const expected = `v0=${createHmac("sha256", config.signingSecret)
    .update(baseString, "utf8")
    .digest("hex")}`;
  return timingSafeStringEqual(expected, signature);
}

function headerValue(request: IncomingMessage, header: string): string | undefined {
  const value = request.headers[header];
  return Array.isArray(value) ? value[0] : value;
}

function timingSafeStringEqual(left: string, right: string): boolean {
  const leftBytes = Buffer.from(left, "utf8");
  const rightBytes = Buffer.from(right, "utf8");
  return leftBytes.length === rightBytes.length && timingSafeEqual(leftBytes, rightBytes);
}

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await startSlackRuntime();
}
