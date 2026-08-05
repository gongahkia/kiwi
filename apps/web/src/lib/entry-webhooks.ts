import { createHmac } from "node:crypto";

import type { TeamEntry } from "@/lib/team-entries";

export interface EntryWebhookEvent {
  actor_id: string | null;
  entry: TeamEntry;
  event: "team_entry.created" | "team_entry.updated";
  team_id: string;
}

export type WebhookFetch = (input: string | URL, init?: RequestInit) => Promise<Response>;

interface WebhookEnv {
  [key: string]: string | undefined;
  WAT_WEBHOOK_SECRET?: string;
  WAT_WEBHOOK_URL?: string;
}

export function signWebhookPayload(input: {
  body: string;
  secret: string;
  timestamp: string;
}): string {
  return `sha256=${createHmac("sha256", input.secret)
    .update(`${input.timestamp}.${input.body}`)
    .digest("hex")}`;
}

export async function dispatchEntryWebhook(
  event: EntryWebhookEvent,
  env: WebhookEnv = process.env,
  fetchImpl: WebhookFetch = fetch
): Promise<{ delivered: boolean; reason?: string }> {
  const url = env.WAT_WEBHOOK_URL?.trim();
  const secret = env.WAT_WEBHOOK_SECRET?.trim();
  if (!url || !secret) return { delivered: false, reason: "not_configured" };

  const timestamp = String(Math.floor(Date.now() / 1000));
  const body = JSON.stringify(event);
  const response = await fetchImpl(url, {
    body,
    headers: {
      "content-type": "application/json",
      "x-wat-event": event.event,
      "x-wat-signature": signWebhookPayload({ body, secret, timestamp }),
      "x-wat-timestamp": timestamp
    },
    method: "POST"
  });
  return response.ok
    ? { delivered: true }
    : { delivered: false, reason: `http_${response.status}` };
}

export async function dispatchEntryWebhookSafely(event: EntryWebhookEvent): Promise<void> {
  try {
    await dispatchEntryWebhook(event);
  } catch (error) {
    console.warn(
      JSON.stringify({
        error: error instanceof Error ? error.message : String(error),
        event: "entry_webhook_failed",
        team_id: event.team_id,
        webhook_event: event.event
      })
    );
  }
}
