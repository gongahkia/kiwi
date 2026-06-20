import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { App, type Receiver, type ReceiverEvent } from "@slack/bolt";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { explainAcronymsShortcutId, registerWatBoltHandlers } from "./wat-bolt.js";

interface ProcessableBoltApp {
  processEvent(event: ReceiverEvent): Promise<void>;
}

interface CapturedRequest {
  body: unknown;
  path: string;
}

class BoltTestReceiver implements Receiver {
  private app: ProcessableBoltApp | null = null;
  readonly acked: unknown[] = [];

  async dispatch(body: Record<string, unknown>): Promise<void> {
    if (!this.app) throw new Error("receiver not initialized");
    await this.app.processEvent({
      ack: async (response?: unknown) => {
        this.acked.push(response ?? true);
      },
      body
    });
  }

  init(app: unknown): void {
    this.app = app as ProcessableBoltApp;
  }

  async start(): Promise<void> {}

  async stop(): Promise<void> {}
}

let baseUrl: string;
let captured: CapturedRequest[];
let server: Server;

beforeEach(async () => {
  captured = [];
  server = createServer(handleRequest);
  await new Promise<void>((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address() as AddressInfo;
  baseUrl = `http://127.0.0.1:${address.port}`;
});

afterEach(async () => {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
});

describe("wat Bolt handlers", () => {
  it("responds to /wat with the top result and disambiguation buttons", async () => {
    const receiver = createWatApp();

    await receiver.dispatch({
      api_app_id: "A_WAT",
      channel_id: "C_DOCS",
      channel_name: "docs",
      command: "/wat",
      response_url: `${baseUrl}/response`,
      team_domain: "example",
      team_id: "T_WAT",
      text: "TLS",
      token: "legacy-token",
      trigger_id: "trigger",
      user_id: "U_ALICE",
      user_name: "alice"
    });

    expect(receiver.acked).toEqual([true]);
    const response = responsePayload("/response");
    expect(response).toMatchObject({
      response_type: "ephemeral",
      text: "TLS: Transport Layer Security"
    });
    expect(JSON.stringify(response)).toContain("QUIC");
    expect(JSON.stringify(response)).toContain("wat_disambiguate");
  });

  it("lets configured admins define team entries from Slack", async () => {
    const receiver = createWatApp({ slackAdminUserIds: ["U_ALICE"] });

    await receiver.dispatch({
      api_app_id: "A_WAT",
      channel_id: "C_DOCS",
      channel_name: "docs",
      command: "/wat-define",
      response_url: `${baseUrl}/response`,
      team_domain: "example",
      team_id: "T_WAT",
      text: "SLO as Service Level Objective -- Reliability target for a service.",
      token: "legacy-token",
      trigger_id: "trigger",
      user_id: "U_ALICE",
      user_name: "alice"
    });

    expect(receiver.acked).toEqual([true]);
    expect(responsePayload("/response")).toMatchObject({
      response_type: "ephemeral",
      text: "Defined SLO as Service Level Objective."
    });
    expect(responsePayload("/team/admin/entries/api")).toMatchObject({
      expansion: "Service Level Objective",
      meaning: "Reliability target for a service.",
      term: "SLO"
    });
  });

  it("queues member suggestions from Slack", async () => {
    const receiver = createWatApp();

    await receiver.dispatch({
      api_app_id: "A_WAT",
      channel_id: "C_DOCS",
      channel_name: "docs",
      command: "/wat-suggest",
      response_url: `${baseUrl}/response`,
      team_domain: "example",
      team_id: "T_WAT",
      text: "RTO as Recovery Time Objective -- Maximum acceptable restore time.",
      token: "legacy-token",
      trigger_id: "trigger",
      user_id: "U_BOB",
      user_name: "bob"
    });

    expect(receiver.acked).toEqual([true]);
    expect(responsePayload("/response")).toMatchObject({
      response_type: "ephemeral",
      text: "Suggested RTO as Recovery Time Objective for admin review."
    });
    expect(responsePayload("/suggest/api")).toMatchObject({
      expansion: "Recovery Time Objective",
      meaning: "Maximum acceptable restore time.",
      term: "RTO"
    });
  });

  it("rejects non-admin define attempts", async () => {
    const receiver = createWatApp({ slackAdminUserIds: ["U_ALICE"] });

    await receiver.dispatch({
      api_app_id: "A_WAT",
      channel_id: "C_DOCS",
      channel_name: "docs",
      command: "/wat-define",
      response_url: `${baseUrl}/response`,
      team_domain: "example",
      team_id: "T_WAT",
      text: "RPO as Recovery Point Objective",
      token: "legacy-token",
      trigger_id: "trigger",
      user_id: "U_BOB",
      user_name: "bob"
    });

    expect(receiver.acked).toEqual([true]);
    expect(responsePayload("/response")).toMatchObject({
      response_type: "ephemeral",
      text: "Only configured Slack workspace admins can define team entries."
    });
    expect(captured.some((item) => item.path === "/team/admin/entries/api")).toBe(false);
  });

  it("responds to the explain-acronyms message shortcut with detected entries", async () => {
    const receiver = createWatApp();

    await receiver.dispatch({
      action_ts: "1700000000.000000",
      callback_id: explainAcronymsShortcutId,
      channel: { id: "C_DOCS", name: "docs" },
      message: {
        text: "Rotate TLS certs before API clients fail.",
        ts: "1700000001.000000",
        type: "message",
        user: "U_ALICE"
      },
      message_ts: "1700000001.000000",
      response_url: `${baseUrl}/response`,
      team: { domain: "example", id: "T_WAT" },
      token: "legacy-token",
      trigger_id: "trigger",
      type: "message_action",
      user: { id: "U_ALICE", name: "alice", team_id: "T_WAT" }
    });

    expect(receiver.acked).toEqual([true]);
    const response = responsePayload("/response");
    expect(response).toMatchObject({ response_type: "ephemeral" });
    expect(JSON.stringify(response)).toContain("TLS");
    expect(JSON.stringify(response)).toContain("Application Programming Interface");
  });

  it("replies in-thread to app mentions", async () => {
    const receiver = createWatApp();

    await receiver.dispatch({
      api_app_id: "A_WAT",
      authorizations: [
        {
          enterprise_id: null,
          is_bot: true,
          team_id: "T_WAT",
          user_id: "U_WAT"
        }
      ],
      event: {
        channel: "C_DOCS",
        text: "<@U_WAT> TLS",
        ts: "1700000002.000000",
        type: "app_mention",
        user: "U_ALICE"
      },
      event_id: "Ev1",
      event_time: 1700000002,
      team_id: "T_WAT",
      token: "legacy-token",
      type: "event_callback"
    });

    expect(receiver.acked).toEqual([true]);
    const response = responsePayload("/api/chat.postMessage");
    expect(response).toMatchObject({
      channel: "C_DOCS",
      text: "TLS: Transport Layer Security",
      thread_ts: "1700000002.000000"
    });
  });
});

function createWatApp(options: { slackAdminUserIds?: string[] } = {}): BoltTestReceiver {
  const receiver = new BoltTestReceiver();
  const app = new App({
    botId: "B_WAT",
    botUserId: "U_WAT",
    clientOptions: {
      slackApiUrl: `${baseUrl}/api/`
    },
    ignoreSelf: false,
    receiver,
    token: "xoxb-test",
    tokenVerificationEnabled: false
  });
  registerWatBoltHandlers(app, {
    slackAdminUserIds: options.slackAdminUserIds,
    watApiBaseUrl: baseUrl
  });
  return receiver;
}

function responsePayload(path: string): Record<string, unknown> {
  const request = captured.find((item) => item.path === path);
  if (!request || !request.body || typeof request.body !== "object") {
    throw new Error(`missing captured request for ${path}`);
  }
  return request.body as Record<string, unknown>;
}

async function handleRequest(request: IncomingMessage, response: ServerResponse): Promise<void> {
  const url = new URL(request.url ?? "/", baseUrl || "http://127.0.0.1");
  if (url.pathname === "/api/v1/search") {
    writeJson(response, 200, searchResponse(url.searchParams.get("q") ?? ""));
    return;
  }

  if (
    url.pathname === "/response" ||
    url.pathname === "/api/chat.postMessage" ||
    url.pathname === "/team/admin/entries/api" ||
    url.pathname === "/suggest/api"
  ) {
    captured.push({ body: await readBody(request), path: url.pathname });
    writeJson(response, 200, { ok: true, ts: "1700000003.000000" });
    return;
  }

  writeJson(response, 404, { error: "not_found" });
}

async function readBody(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  if (!raw) return null;
  const contentType = request.headers["content-type"] ?? "";
  if (contentType.includes("application/json")) return JSON.parse(raw);
  const params = new URLSearchParams(raw);
  const payload = params.get("payload");
  if (payload) return JSON.parse(payload);
  return Object.fromEntries(params.entries());
}

function searchResponse(query: string) {
  const normalized = query.trim().toUpperCase();
  if (normalized === "TLS") {
    return {
      matches: [
        {
          entry: {
            expansions: ["Transport Layer Security"],
            id: "seed-tls",
            meaning_short: "Encrypts transport connections.",
            term: "TLS"
          }
        },
        {
          entry: {
            expansions: ["Quick UDP Internet Connections"],
            id: "seed-quic",
            meaning_short: "A transport protocol using TLS.",
            term: "QUIC"
          }
        }
      ]
    };
  }
  if (normalized === "API") {
    return {
      matches: [
        {
          entry: {
            expansions: ["Application Programming Interface"],
            id: "seed-api",
            meaning_short: "A software interface.",
            term: "API"
          }
        }
      ]
    };
  }
  return { matches: [] };
}

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}
