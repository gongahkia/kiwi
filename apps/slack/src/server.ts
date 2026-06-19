import { createServer, type IncomingMessage, type ServerResponse } from "node:http";

export interface SlackRuntimeConfig {
  appToken?: string;
  httpMode: boolean;
  port: number;
  socketMode: boolean;
  watApiBaseUrl: string;
}

export function configFromEnv(env: NodeJS.ProcessEnv = process.env): SlackRuntimeConfig {
  return {
    appToken: env.SLACK_APP_TOKEN,
    httpMode: env.SLACK_HTTP_MODE !== "false",
    port: Number(env.PORT ?? 3001),
    socketMode: env.SLACK_SOCKET_MODE === "true",
    watApiBaseUrl: env.WAT_API_BASE_URL ?? "http://localhost:3000"
  };
}

export function validateConfig(config: SlackRuntimeConfig): void {
  if (!Number.isFinite(config.port) || config.port < 1) {
    throw new Error("PORT must be a positive number");
  }
  if (config.socketMode && !config.appToken) {
    throw new Error("SLACK_APP_TOKEN is required when SLACK_SOCKET_MODE=true");
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
        wat_api_base_url: config.watApiBaseUrl
      });
      return;
    }

    if (request.method === "POST" && request.url === "/slack/events") {
      const payload = await readJson(request);
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

async function readJson(request: IncomingMessage): Promise<Record<string, unknown> | null> {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  if (chunks.length === 0) return null;
  return JSON.parse(Buffer.concat(chunks).toString("utf8")) as Record<string, unknown>;
}

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await startSlackRuntime();
}
