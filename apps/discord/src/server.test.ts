import { generateKeyPairSync, sign as cryptoSign, type KeyObject } from "node:crypto";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it } from "vitest";

import { MemoryDiscordInstallStore } from "./discord-install-store.js";
import { InMemoryDiscordMonitor } from "./discord-monitoring.js";
import {
  configFromEnv,
  createDiscordHttpHandler,
  parseDiscordGuildWatTeamMap,
  validateConfig,
  verifyDiscordSignature,
  type DiscordRuntimeConfig,
  type DiscordRuntimeDeps
} from "./server.js";

interface CapturedRequest {
  body?: unknown;
  headers: Record<string, string>;
  path: string;
  q?: string;
}

const servers: Server[] = [];

afterEach(async () => {
  await Promise.all(
    servers.map(
      (server) =>
        new Promise<void>((resolve, reject) =>
          server.close((error) => (error ? reject(error) : resolve()))
        )
    )
  );
  servers.length = 0;
});

describe("Discord runtime", () => {
  it("verifies Ed25519 signatures", () => {
    const material = signingMaterial();
    const rawBody = Buffer.from(JSON.stringify({ type: 1 }));
    const timestamp = "1700000000";
    const signature = signDiscordBody(rawBody, timestamp, material.privateKey);

    expect(
      verifyDiscordSignature({
        publicKey: material.publicKeyHex,
        rawBody,
        signature,
        timestamp
      })
    ).toBe(true);
    expect(
      verifyDiscordSignature({
        publicKey: material.publicKeyHex,
        rawBody,
        signature: `${signature.slice(0, -2)}00`,
        timestamp
      })
    ).toBe(false);
  });

  it("responds to Discord PING interactions", async () => {
    const material = signingMaterial();
    const url = await listen(config(material.publicKeyHex));

    const response = await postInteraction(url, { type: 1 }, material);

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ type: 1 });
  });

  it("rejects unsigned Discord interactions", async () => {
    const material = signingMaterial();
    const url = await listen(config(material.publicKeyHex));

    const response = await fetch(new URL("/discord/interactions", url), {
      body: JSON.stringify({ type: 1 }),
      method: "POST"
    });

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "invalid_discord_signature" });
  });

  it("serves health and protected metrics", async () => {
    const material = signingMaterial();
    const monitor = new InMemoryDiscordMonitor();
    monitor.increment("discord_command_total", { command: "wat" });
    const url = await listen(
      {
        ...config(material.publicKeyHex),
        metricsToken: "metrics-secret"
      },
      { monitor }
    );

    const health = await fetch(new URL("/healthz", url));
    const unauthorized = await fetch(new URL("/metrics", url));
    const authorized = await fetch(new URL("/metrics", url), {
      headers: { authorization: "Bearer metrics-secret" }
    });

    expect(health.status).toBe(200);
    expect(await health.json()).toMatchObject({ service: "discord", status: "ok" });
    expect(unauthorized.status).toBe(401);
    expect(authorized.status).toBe(200);
    expect(await authorized.text()).toContain('discord_command_total{command="wat"} 1');
  });

  it("redirects Discord installs to OAuth authorize", async () => {
    const material = signingMaterial();
    const url = await listen({
      ...config(material.publicKeyHex),
      applicationId: "app_123",
      installGuildId: "guild_123",
      installIntegrationType: "0",
      installScopes: ["applications.commands"]
    });

    const response = await fetch(new URL("/discord/install", url), { redirect: "manual" });
    const location = new URL(response.headers.get("location")!);

    expect(response.status).toBe(302);
    expect(location.origin).toBe("https://discord.com");
    expect(location.pathname).toBe("/oauth2/authorize");
    expect(location.searchParams.get("client_id")).toBe("app_123");
    expect(location.searchParams.get("guild_id")).toBe("guild_123");
    expect(location.searchParams.get("scope")).toBe("applications.commands");
  });

  it("handles /wat with DB-backed guild mapping and scoped wat headers", async () => {
    const material = signingMaterial();
    const store = new MemoryDiscordInstallStore();
    const captured: CapturedRequest[] = [];
    await store.upsert({
      adminRoleIds: [],
      appId: "app_123",
      discordGuildId: "guild_123",
      installedAt: "2026-06-25T00:00:00.000Z",
      updatedAt: "2026-06-25T00:00:00.000Z",
      watTeamId: "team_123"
    });
    const url = await listen(
      {
        ...config(material.publicKeyHex),
        watApiKey: "wat-key"
      },
      {
        fetchLookup: lookupFetch(captured),
        installStore: store
      }
    );

    const response = await postInteraction(url, commandInteraction("wat", "TLS"), material);
    const body = (await response.json()) as { data?: { content?: string } };

    expect(body.data?.content).toContain("TLS");
    expect(captured[0]).toMatchObject({
      headers: {
        authorization: "Bearer wat-key",
        "x-wat-team-id": "team_123",
        "x-wat-user-id": "discord:user_123"
      },
      path: "/api/v1/search",
      q: "TLS"
    });
  });

  it("queues /wat-suggest through the team-scoped suggestion API", async () => {
    const material = signingMaterial();
    const store = mappedInstallStore();
    const captured: CapturedRequest[] = [];
    const url = await listen(
      {
        ...config(material.publicKeyHex),
        watApiKey: "wat-key"
      },
      {
        fetchWrite: writeFetch(captured),
        installStore: store
      }
    );

    const response = await postInteraction(
      url,
      commandInteraction("wat-suggest", "SLO", [
        { name: "expansion", value: "Service Level Objective" },
        { name: "meaning", value: "Reliability target." }
      ]),
      material
    );
    const body = (await response.json()) as { data?: { content?: string } };

    expect(body.data?.content).toContain("Suggested SLO");
    expect(captured[0]).toMatchObject({
      body: {
        expansion: "Service Level Objective",
        meaning: "Reliability target.",
        term: "SLO"
      },
      headers: {
        authorization: "Bearer wat-key",
        "x-wat-team-id": "team_123",
        "x-wat-user-id": "discord:user_123"
      },
      path: "/api/v1/suggestions"
    });
  });

  it("gates /wat-define by Discord admin roles", async () => {
    const material = signingMaterial();
    const captured: CapturedRequest[] = [];
    const url = await listen(
      {
        ...config(material.publicKeyHex),
        watApiKey: "wat-key"
      },
      {
        fetchWrite: writeFetch(captured),
        installStore: mappedInstallStore(["role_admin"])
      }
    );

    const denied = await postInteraction(
      url,
      commandInteraction("wat-define", "SLO", [
        { name: "expansion", value: "Service Level Objective" },
        { name: "meaning", value: "Reliability target." }
      ]),
      material
    );
    const allowed = await postInteraction(
      url,
      commandInteraction(
        "wat-define",
        "SLO",
        [
          { name: "expansion", value: "Service Level Objective" },
          { name: "meaning", value: "Reliability target." }
        ],
        ["role_admin"]
      ),
      material
    );
    const deniedBody = (await denied.json()) as { data?: { content?: string } };
    const allowedBody = (await allowed.json()) as { data?: { content?: string } };

    expect(deniedBody.data?.content).toContain("Only configured Discord admins");
    expect(allowedBody.data?.content).toContain("Defined SLO");
    expect(captured).toHaveLength(1);
    expect(captured[0]).toMatchObject({
      body: {
        expansion: "Service Level Objective",
        mode: "upsert",
        scope: "team",
        term: "SLO"
      },
      path: "/api/v1/custom-entries"
    });
  });

  it("extracts acronyms from Discord message commands", async () => {
    const material = signingMaterial();
    const captured: CapturedRequest[] = [];
    const url = await listen(config(material.publicKeyHex), {
      fetchLookup: lookupFetch(captured)
    });

    const response = await postInteraction(
      url,
      {
        ...commandInteraction("Explain acronyms", "ignored"),
        data: {
          name: "Explain acronyms",
          resolved: {
            messages: {
              message_123: { content: "TLS and SLO matter." }
            }
          },
          target_id: "message_123",
          type: 3
        }
      },
      material
    );
    const body = (await response.json()) as { data?: { content?: string } };

    expect(body.data?.content).toContain("TLS");
    expect(captured.map((request) => request.q)).toEqual(["TLS", "SLO"]);
  });

  it("validates and reads config from env", () => {
    expect(() =>
      validateConfig({
        port: 3002,
        watApiBaseUrl: "http://web:3000"
      })
    ).toThrow("DISCORD_PUBLIC_KEY is required");

    expect(
      configFromEnv({
        DISCORD_ADMIN_ROLE_IDS: "R_ADMIN, R_OWNER",
        DISCORD_ADMIN_USER_IDS: "U_ADMIN",
        DISCORD_APPLICATION_ID: "app_123",
        DISCORD_BOT_TOKEN: "bot-token",
        DISCORD_DATABASE_URL: "postgres://wat:wat@localhost:5432/wat",
        DISCORD_INSTALL_GUILD_ID: "guild_123",
        DISCORD_INSTALL_SCOPES: "applications.commands bot",
        DISCORD_INSTALL_STORE: "postgres",
        DISCORD_METRICS_TOKEN: "metrics-secret",
        DISCORD_PUBLIC_KEY: "a".repeat(64),
        PORT: "4002",
        WAT_API_BASE_URL: "http://web:3000",
        WAT_API_KEY: "wat-key",
        WAT_DISCORD_GUILD_MAP: "guild_123:team_123",
        WAT_TEAM_ID: "team_fallback"
      })
    ).toMatchObject({
      applicationId: "app_123",
      discordAdminRoleIds: ["R_ADMIN", "R_OWNER"],
      discordAdminUserIds: ["U_ADMIN"],
      discordGuildWatTeamMap: { guild_123: "team_123" },
      installStore: "postgres",
      installGuildId: "guild_123",
      installScopes: ["applications.commands", "bot"],
      port: 4002
    });
    expect(parseDiscordGuildWatTeamMap("G1:T1, bad, G2:T2")).toEqual({ G1: "T1", G2: "T2" });
  });
});

function signingMaterial(): { privateKey: KeyObject; publicKeyHex: string } {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const der = publicKey.export({ format: "der", type: "spki" });
  return {
    privateKey,
    publicKeyHex: Buffer.from(der).subarray(-32).toString("hex")
  };
}

function signDiscordBody(rawBody: Buffer, timestamp: string, privateKey: KeyObject): string {
  return cryptoSign(
    null,
    Buffer.concat([Buffer.from(timestamp, "utf8"), rawBody]),
    privateKey
  ).toString("hex");
}

async function listen(config: DiscordRuntimeConfig, deps: DiscordRuntimeDeps = {}): Promise<URL> {
  const server = createServer(createDiscordHttpHandler(config, deps));
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  return new URL(`http://127.0.0.1:${address.port}`);
}

async function postInteraction(
  baseUrl: URL,
  payload: unknown,
  material: { privateKey: KeyObject; publicKeyHex: string }
): Promise<Response> {
  const rawBody = Buffer.from(JSON.stringify(payload));
  const timestamp = "1700000000";
  return fetch(new URL("/discord/interactions", baseUrl), {
    body: rawBody,
    headers: {
      "content-type": "application/json",
      "x-signature-ed25519": signDiscordBody(rawBody, timestamp, material.privateKey),
      "x-signature-timestamp": timestamp
    },
    method: "POST"
  });
}

function config(publicKey: string): DiscordRuntimeConfig {
  return {
    installStore: "memory",
    port: 0,
    publicKey,
    watApiBaseUrl: "http://wat.test"
  };
}

function commandInteraction(
  command: string,
  term: string,
  options: Array<{ name: string; value: string }> = [],
  roles: string[] = []
) {
  return {
    channel: { id: "channel_123", name: "eng" },
    channel_id: "channel_123",
    data: {
      name: command,
      options: [{ name: "term", value: term }, ...options],
      type: 1
    },
    guild_id: "guild_123",
    member: {
      permissions: "0",
      roles,
      user: { id: "user_123", username: "alice" }
    },
    type: 2
  };
}

function lookupFetch(captured: CapturedRequest[]): typeof fetch {
  return async (input, init) => {
    const url = new URL(String(input));
    captured.push({
      headers: Object.fromEntries(new Headers(init?.headers).entries()),
      path: url.pathname,
      q: url.searchParams.get("q") ?? undefined
    });
    return Response.json({
      matches: [
        {
          entry: {
            contemporaries: ["SSL", "DTLS"],
            expansions: [
              url.searchParams.get("q") === "SLO"
                ? "Service Level Objective"
                : "Transport Layer Security"
            ],
            meaning_short: "Lookup result.",
            term: url.searchParams.get("q")
          }
        }
      ]
    });
  };
}

function writeFetch(captured: CapturedRequest[]): typeof fetch {
  return async (input, init) => {
    const url = new URL(String(input));
    captured.push({
      body: init?.body ? JSON.parse(String(init.body)) : undefined,
      headers: Object.fromEntries(new Headers(init?.headers).entries()),
      path: url.pathname
    });
    return Response.json({ ok: true }, { status: 201 });
  };
}

function mappedInstallStore(adminRoleIds: string[] = []): MemoryDiscordInstallStore {
  const store = new MemoryDiscordInstallStore();
  void store.upsert({
    adminRoleIds,
    appId: "app_123",
    discordGuildId: "guild_123",
    installedAt: "2026-06-25T00:00:00.000Z",
    updatedAt: "2026-06-25T00:00:00.000Z",
    watTeamId: "team_123"
  });
  return store;
}
