import { createHmac } from "node:crypto";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { describe, expect, it, vi } from "vitest";

import { dispatchEntryWebhook, signWebhookPayload } from "./entry-webhooks";
import type { TeamEntry } from "./team-entries";

const entry: TeamEntry = {
  domains: ["ops"],
  expansion: "Recovery Time Objective",
  id: "team-route-rto",
  meaning: "Restore target.",
  sources: [],
  term: "RTO"
};

describe("entry webhooks", () => {
  it("signs timestamped payloads", () => {
    const body = JSON.stringify({ event: "team_entry.created" });
    const signature = signWebhookPayload({ body, secret: "secret", timestamp: "1783656000" });

    expect(signature).toBe(
      `sha256=${createHmac("sha256", "secret").update(`1783656000.${body}`).digest("hex")}`
    );
  });

  it("posts signed entry webhook payloads", async () => {
    const fetchImpl = vi.fn().mockResolvedValue(new Response(null, { status: 204 }));

    await expect(
      dispatchEntryWebhook(
        { actor_id: "user_1", entry, event: "team_entry.created", team_id: "team_1" },
        { WAT_WEBHOOK_SECRET: "secret", WAT_WEBHOOK_URL: "https://hooks.example.test/wat" },
        fetchImpl
      )
    ).resolves.toEqual({ delivered: true });

    const [url, init] = fetchImpl.mock.calls[0]!;
    const headers = init.headers as Record<string, string>;
    expect(url).toBe("https://hooks.example.test/wat");
    expect(headers["x-wat-event"]).toBe("team_entry.created");
    expect(headers["x-wat-signature"]).toMatch(/^sha256=[a-f0-9]{64}$/u);
    expect(JSON.parse(init.body as string)).toMatchObject({
      entry: { id: "team-route-rto" },
      team_id: "team_1"
    });
  });

  it("delivers signed payloads to a webhook receiver", async () => {
    let received:
      | {
          body: string;
          event: string | undefined;
          signature: string | undefined;
          timestamp: string;
        }
      | undefined;
    const server = createServer(async (request: IncomingMessage, response: ServerResponse) => {
      const chunks: Buffer[] = [];
      for await (const chunk of request) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      }
      received = {
        body: Buffer.concat(chunks).toString("utf8"),
        event: firstHeader(request.headers["x-wat-event"]),
        signature: firstHeader(request.headers["x-wat-signature"]),
        timestamp: firstHeader(request.headers["x-wat-timestamp"]) ?? ""
      };
      response.writeHead(204);
      response.end();
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    try {
      const address = server.address() as AddressInfo;
      await expect(
        dispatchEntryWebhook(
          { actor_id: "user_1", entry, event: "team_entry.updated", team_id: "team_1" },
          {
            WAT_WEBHOOK_SECRET: "secret",
            WAT_WEBHOOK_URL: `http://127.0.0.1:${address.port}/webhook`
          }
        )
      ).resolves.toEqual({ delivered: true });
    } finally {
      await new Promise<void>((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
      });
    }

    expect(received?.event).toBe("team_entry.updated");
    expect(JSON.parse(received?.body ?? "{}")).toMatchObject({
      entry: { id: "team-route-rto" },
      team_id: "team_1"
    });
    expect(received?.signature).toBe(
      signWebhookPayload({
        body: received?.body ?? "",
        secret: "secret",
        timestamp: received?.timestamp ?? ""
      })
    );
  });
});

function firstHeader(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}
