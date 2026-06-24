import { readFileSync } from "node:fs";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { App, type Receiver, type ReceiverEvent } from "@slack/bolt";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { explainAcronymsShortcutId, registerWatBoltHandlers } from "./wat-bolt.js";
import {
  MemoryRateLimitStore,
  type SlackRateLimitStore,
  type WorkspaceRateLimitConfig
} from "./workspace-rate-limit.js";

interface ProcessableBoltApp {
  processEvent(event: ReceiverEvent): Promise<void>;
}

interface CapturedRequest {
  body: unknown;
  headers: WatHeaders;
  path: string;
}

interface CapturedSearchRequest {
  context: string;
  headers: WatHeaders;
  q: string;
}

interface WatHeaders {
  authorization?: string;
  xWatTeamId?: string;
  xWatUserId?: string;
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
let searchRequests: CapturedSearchRequest[];
let server: Server;
const referenceTerms = [
  { peers: ["Docker Swarm", "Nomad", "ECS"], term: "Kubernetes" },
  { peers: ["RabbitMQ", "NATS", "Redpanda", "Pulsar"], term: "Kafka" },
  { peers: ["MySQL", "MariaDB", "CockroachDB", "YugabyteDB"], term: "Postgres" },
  { peers: ["Pulumi", "OpenTofu", "CloudFormation"], term: "Terraform" },
  { peers: ["New Relic", "Grafana Cloud", "Honeycomb", "Splunk"], term: "Datadog" }
];
const referenceEntries = loadReferenceEntries();

beforeEach(async () => {
  captured = [];
  searchRequests = [];
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
    expect(JSON.stringify(response)).toContain("Alternatives: SSL, DTLS");
  });

  it("escapes user-provided glossary fields in Slack output", async () => {
    const receiver = createWatApp();

    await receiver.dispatch({
      api_app_id: "A_WAT",
      channel_id: "C_DOCS",
      channel_name: "docs",
      command: "/wat",
      response_url: `${baseUrl}/response`,
      team_domain: "example",
      team_id: "T_WAT",
      text: "XSS",
      token: "legacy-token",
      trigger_id: "trigger",
      user_id: "U_ALICE",
      user_name: "alice"
    });

    const response = JSON.stringify(responsePayload("/response"));
    expect(response).toContain("&lt;!channel&gt;");
    expect(response).toContain("&lt;script&gt;alert(1)&lt;/script&gt;");
    expect(response).toContain("Fish &amp; Chips");
    expect(response).not.toContain("<!channel>");
    expect(response).not.toContain("<script>");
  });

  it("sends scoped wat API headers on Slack lookups", async () => {
    const receiver = createWatApp({ watApiKey: "wat-team-key", watTeamId: "wat-team-123" });

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

    expect(searchRequests[0]?.headers).toEqual({
      authorization: "Bearer wat-team-key",
      xWatTeamId: "wat-team-123",
      xWatUserId: "slack:U_ALICE"
    });
  });

  it("responds to /wat-alt with resolved alternatives", async () => {
    const receiver = createWatApp();

    await receiver.dispatch({
      api_app_id: "A_WAT",
      channel_id: "C_DOCS",
      channel_name: "docs",
      command: "/wat-alt",
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
      text: "Alternatives for TLS: SSL, DTLS"
    });
    expect(JSON.stringify(response)).toContain("SSL: Secure Sockets Layer");
    expect(JSON.stringify(response)).toContain("Legacy transport encryption.");
    expect(JSON.stringify(response)).toContain("DTLS: Datagram Transport Layer Security");
  });

  it("responds to /wat-alt for reference entries", async () => {
    const receiver = createWatApp();

    for (const reference of referenceTerms) {
      await receiver.dispatch({
        api_app_id: "A_WAT",
        channel_id: "C_DOCS",
        channel_name: "docs",
        command: "/wat-alt",
        response_url: `${baseUrl}/response`,
        team_domain: "example",
        team_id: "T_WAT",
        text: reference.term,
        token: "legacy-token",
        trigger_id: "trigger",
        user_id: "U_ALICE",
        user_name: "alice"
      });
    }

    const responses = responsePayloads("/response").slice(-referenceTerms.length);
    expect(responses).toHaveLength(referenceTerms.length);
    for (const [index, reference] of referenceTerms.entries()) {
      const response = responses[index]!;
      expect(response).toMatchObject({
        response_type: "ephemeral",
        text: `Alternatives for ${reference.term}: ${reference.peers.join(", ")}`
      });
      for (const peer of reference.peers) {
        expect(JSON.stringify(response)).toContain(peer);
      }
    }
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
    const receiver = createWatApp({ watApiKey: "wat-team-key", watTeamId: "wat-team-123" });

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
    expect(capturedRequest("/suggest/api").headers).toEqual({
      authorization: "Bearer wat-team-key",
      xWatTeamId: "wat-team-123",
      xWatUserId: "slack:U_BOB"
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
      channel: { id: "C_DOCS", name: "docs-channel-secret" },
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
    expect(searchRequests.map(({ context, q }) => ({ context, q }))).toEqual([
      { context: "Rotate TLS certs before API clients fail.", q: "TLS" },
      { context: "Rotate TLS certs before API clients fail.", q: "API" }
    ]);
    expect(JSON.stringify(searchRequests)).not.toContain("docs-channel-secret");
  });

  it("throttles Slack command bursts by channel", async () => {
    const receiver = createWatApp({
      rateLimitConfig: {
        channelLimit: 1,
        limit: 99,
        userLimit: 99,
        windowMs: 60_000,
        workspaceLimit: 99
      }
    });

    const command = {
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
    };

    await receiver.dispatch(command);
    await receiver.dispatch({ ...command, text: "SSL", user_id: "U_BOB" });

    expect(receiver.acked).toEqual([true, true]);
    expect(responsePayloads("/response").at(-1)).toMatchObject({
      response_type: "ephemeral",
      text: "Slack rate limit exceeded for channel. Retry after 60s."
    });
    expect(searchRequests.map((request) => request.q)).toEqual(["TLS"]);
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

function createWatApp(
  options: {
    rateLimitConfig?: WorkspaceRateLimitConfig;
    rateLimitStore?: SlackRateLimitStore;
    slackAdminUserIds?: string[];
    watApiKey?: string;
    watTeamId?: string;
  } = {}
): BoltTestReceiver {
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
    rateLimitConfig: options.rateLimitConfig ?? {
      channelLimit: 100,
      limit: 100,
      userLimit: 100,
      windowMs: 60_000,
      workspaceLimit: 100
    },
    rateLimitStore: options.rateLimitStore ?? new MemoryRateLimitStore(),
    slackAdminUserIds: options.slackAdminUserIds,
    watApiKey: options.watApiKey,
    watApiBaseUrl: baseUrl,
    watTeamId: options.watTeamId
  });
  return receiver;
}

function responsePayloads(path: string): Record<string, unknown>[] {
  return captured
    .filter((item) => item.path === path && item.body && typeof item.body === "object")
    .map((item) => item.body as Record<string, unknown>);
}

function responsePayload(path: string): Record<string, unknown> {
  const request = capturedRequest(path);
  return request.body as Record<string, unknown>;
}

function capturedRequest(path: string): CapturedRequest {
  const [request] = captured.filter((item) => item.path === path);
  if (!request) {
    throw new Error(`missing captured request for ${path}`);
  }
  return request;
}

async function handleRequest(request: IncomingMessage, response: ServerResponse): Promise<void> {
  const url = new URL(request.url ?? "/", baseUrl || "http://127.0.0.1");
  if (url.pathname === "/api/v1/search") {
    searchRequests.push({
      context: url.searchParams.get("context") ?? "",
      headers: watHeaders(request),
      q: url.searchParams.get("q") ?? ""
    });
    writeJson(response, 200, searchResponse(url.searchParams.get("q") ?? ""));
    return;
  }

  if (
    url.pathname === "/response" ||
    url.pathname === "/api/chat.postMessage" ||
    url.pathname === "/team/admin/entries/api" ||
    url.pathname === "/suggest/api"
  ) {
    captured.push({
      body: await readBody(request),
      headers: watHeaders(request),
      path: url.pathname
    });
    writeJson(response, 200, { ok: true, ts: "1700000003.000000" });
    return;
  }

  writeJson(response, 404, { error: "not_found" });
}

function watHeaders(request: IncomingMessage): WatHeaders {
  return {
    authorization: firstHeader(request.headers.authorization),
    xWatTeamId: firstHeader(request.headers["x-wat-team-id"]),
    xWatUserId: firstHeader(request.headers["x-wat-user-id"])
  };
}

function firstHeader(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
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
  const reference = referenceEntries.get(query.trim().toLowerCase());
  if (reference) {
    return { matches: [{ entry: reference }] };
  }

  if (normalized === "TLS") {
    return {
      matches: [
        {
          entry: {
            contemporaries: ["SSL", "DTLS"],
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
  if (normalized === "SSL") {
    return {
      matches: [
        {
          entry: {
            expansions: ["Secure Sockets Layer"],
            id: "seed-ssl",
            meaning_short: "Legacy transport encryption.",
            term: "SSL"
          }
        }
      ]
    };
  }
  if (normalized === "DTLS") {
    return {
      matches: [
        {
          entry: {
            expansions: ["Datagram Transport Layer Security"],
            id: "seed-dtls",
            meaning_short: "TLS for datagram transports.",
            term: "DTLS"
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
  if (normalized === "XSS") {
    return {
      matches: [
        {
          entry: {
            contemporaries: ["<svg onload=alert(1)>"],
            expansions: ["<script>alert(1)</script>"],
            id: "seed-xss",
            meaning_short: "Fish & Chips",
            term: "<!channel>"
          }
        }
      ]
    };
  }
  return { matches: [] };
}

function loadReferenceEntries(): Map<
  string,
  {
    contemporaries: string[];
    expansions: string[];
    id: string;
    meaning_short: string;
    term: string;
  }
> {
  const corpus = JSON.parse(
    readFileSync(
      new URL("../../../data/deltas/2026-06-23/contemporaries-seed.json", import.meta.url),
      "utf8"
    )
  ) as {
    entries: Array<{
      contemporaries: string[];
      expansions: string[];
      id: string;
      meaning_short: string;
      term: string;
    }>;
  };
  return new Map(corpus.entries.map((entry) => [entry.term.toLowerCase(), entry]));
}

function writeJson(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}
