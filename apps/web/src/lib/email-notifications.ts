import { randomUUID } from "node:crypto";
import { connect as netConnect } from "node:net";
import { connect as tlsConnect } from "node:tls";

import { getTeamMember } from "./team-members";
import type { SuggestedEdit, SuggestedEditStatus } from "./suggestions";

export interface EmailNotification {
  body: string;
  created_at: string;
  event: string;
  id: string;
  subject: string;
  to: string;
}

interface EmailEnv {
  EMAIL_FROM?: string;
  EMAIL_SERVER?: string;
  [key: string]: string | undefined;
  WAT_EMAIL_NOTIFICATIONS?: string;
}

interface SmtpMessage {
  body: string;
  from: string;
  subject: string;
  to: string;
}

const outbox: EmailNotification[] = [];
const smtpTimeoutMs = 5000;

function enabled(env: EmailEnv): boolean {
  return env.WAT_EMAIL_NOTIFICATIONS === "1" || env.WAT_EMAIL_NOTIFICATIONS === "true";
}

function recipientForActor(actorId: string): string | null {
  const member = getTeamMember(actorId);
  if (member) return member.email;
  return actorId.includes("@") ? actorId : null;
}

function smtpAddress(value: string): string {
  return value.match(/<([^>]+)>/)?.[1]?.trim() ?? value.trim();
}

function dotStuff(value: string): string {
  return value
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .split("\n")
    .map((line) => (line.startsWith(".") ? `.${line}` : line))
    .join("\r\n");
}

function messageData(message: SmtpMessage, messageId: string): string {
  return [
    `From: ${message.from}`,
    `To: ${message.to}`,
    `Subject: ${message.subject}`,
    `Date: ${new Date().toUTCString()}`,
    `Message-ID: <${messageId}@wat.local>`,
    "MIME-Version: 1.0",
    'Content-Type: text/plain; charset="utf-8"',
    "",
    dotStuff(message.body)
  ].join("\r\n");
}

async function smtpSend(server: string, message: SmtpMessage, messageId: string) {
  const url = new URL(server);
  const secure = url.protocol === "smtps:";
  if (!secure && url.protocol !== "smtp:")
    throw new Error("EMAIL_SERVER must use smtp:// or smtps://");

  const port = Number(url.port || (secure ? 465 : 25));
  const socket = secure
    ? tlsConnect({ host: url.hostname, port, servername: url.hostname })
    : netConnect({ host: url.hostname, port });
  socket.setTimeout(smtpTimeoutMs);

  const lines: string[] = [];
  const waiters: Array<() => void> = [];
  let buffered = "";
  let failed: Error | null = null;

  function wake() {
    waiters.splice(0).forEach((resolve) => resolve());
  }

  socket.on("data", (chunk) => {
    buffered += chunk.toString("utf8");
    for (;;) {
      const index = buffered.indexOf("\n");
      if (index === -1) break;
      lines.push(buffered.slice(0, index).replace(/\r$/, ""));
      buffered = buffered.slice(index + 1);
    }
    wake();
  });
  socket.on("error", (error) => {
    failed = error;
    wake();
  });
  socket.on("timeout", () => {
    failed = new Error("SMTP timed out");
    socket.destroy(failed);
    wake();
  });

  function write(command: string) {
    socket.write(`${command}\r\n`);
  }

  async function readReply(expected: number) {
    const parts: string[] = [];
    for (;;) {
      if (failed) throw failed;
      if (lines.length === 0) {
        await new Promise<void>((resolve) => waiters.push(resolve));
        continue;
      }

      const line = lines.shift()!;
      parts.push(line);
      const code = Number(line.slice(0, 3));
      const done = line.length < 4 || line[3] === " ";
      if (done) {
        if (code !== expected)
          throw new Error(`SMTP expected ${expected}, got ${parts.join(" | ")}`);
        return;
      }
    }
  }

  try {
    await readReply(220);
    write("EHLO localhost");
    await readReply(250);
    if (url.username || url.password) {
      const auth = Buffer.from(
        `\0${decodeURIComponent(url.username)}\0${decodeURIComponent(url.password)}`,
        "utf8"
      ).toString("base64");
      write(`AUTH PLAIN ${auth}`);
      await readReply(235);
    }
    write(`MAIL FROM:<${smtpAddress(message.from)}>`);
    await readReply(250);
    write(`RCPT TO:<${smtpAddress(message.to)}>`);
    await readReply(250);
    write("DATA");
    await readReply(354);
    write(`${messageData(message, messageId)}\r\n.`);
    await readReply(250);
    write("QUIT");
    await readReply(221);
  } finally {
    socket.end();
  }
}

export async function sendSuggestionOutcomeEmail(
  suggestion: SuggestedEdit,
  status: SuggestedEditStatus,
  env: EmailEnv = process.env
): Promise<EmailNotification | null> {
  if (!enabled(env) || (status !== "approved" && status !== "rejected")) return null;

  const recipient = recipientForActor(suggestion.actor_id);
  if (!recipient) return null;
  if (!env.EMAIL_SERVER)
    throw new Error("EMAIL_SERVER is required when WAT_EMAIL_NOTIFICATIONS is enabled");

  const notification: EmailNotification = {
    body: `Suggestion ${suggestion.id} was ${status}.`,
    created_at: new Date().toISOString(),
    event: `suggestion.${status}`,
    id: randomUUID(),
    subject: `wat suggestion ${status}`,
    to: recipient
  };
  await smtpSend(
    env.EMAIL_SERVER,
    {
      body: notification.body,
      from: env.EMAIL_FROM ?? "wat@localhost",
      subject: notification.subject,
      to: notification.to
    },
    notification.id
  );
  outbox.push(structuredClone(notification));
  return structuredClone(notification);
}

export function getEmailOutbox(): EmailNotification[] {
  return structuredClone(outbox);
}

export function resetEmailOutboxForTest() {
  outbox.length = 0;
}
