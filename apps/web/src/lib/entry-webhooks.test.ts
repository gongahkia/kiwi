import { createHmac } from "node:crypto";
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
});
