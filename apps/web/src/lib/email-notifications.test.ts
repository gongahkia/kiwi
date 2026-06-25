import { createServer, type Server } from "node:net";

import { describe, expect, it } from "vitest";

import {
  getEmailOutbox,
  resetEmailOutboxForTest,
  sendSuggestionOutcomeEmail
} from "./email-notifications";
import {
  resetSuggestedEditsForTest,
  submitNewEntrySuggestion,
  validateSuggestedEntry
} from "./suggestions";

async function smtpFixture() {
  const messages: string[] = [];
  const server = createServer((socket) => {
    let data = "";
    let message = "";
    let readingData = false;
    socket.write("220 test smtp\r\n");
    socket.on("data", (chunk) => {
      data += chunk.toString("utf8");
      for (;;) {
        const index = data.indexOf("\n");
        if (index === -1) break;
        const line = data.slice(0, index).replace(/\r$/, "");
        data = data.slice(index + 1);
        if (readingData) {
          if (line === ".") {
            messages.push(message);
            message = "";
            readingData = false;
            socket.write("250 queued\r\n");
          } else {
            message += `${line}\n`;
          }
          continue;
        }
        if (line.startsWith("EHLO")) socket.write("250-test\r\n250 AUTH PLAIN\r\n");
        else if (line.startsWith("AUTH")) socket.write("235 ok\r\n");
        else if (line.startsWith("MAIL FROM")) socket.write("250 ok\r\n");
        else if (line.startsWith("RCPT TO")) socket.write("250 ok\r\n");
        else if (line === "DATA") {
          readingData = true;
          socket.write("354 send data\r\n");
        } else if (line === "QUIT") {
          socket.write("221 bye\r\n");
          socket.end();
        } else socket.write("250 ok\r\n");
      }
    });
  });

  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("smtp fixture failed");
  return {
    messages,
    url: `smtp://127.0.0.1:${address.port}`,
    close: () => new Promise<void>((resolve, reject) => closeServer(server, resolve, reject))
  };
}

function closeServer(server: Server, resolve: () => void, reject: (error: Error) => void) {
  server.close((error) => (error ? reject(error) : resolve()));
}

describe("email notifications", () => {
  it("sends outcome email when enabled", async () => {
    resetEmailOutboxForTest();
    resetSuggestedEditsForTest();
    const smtp = await smtpFixture();
    const input = validateSuggestedEntry({
      domains: ["web"],
      expansion: "Document Object Model",
      meaning: "Browser document tree API.",
      source_url: "https://example.com/dom",
      term: "DOM"
    });
    const suggestion = await submitNewEntrySuggestion("team_1", "user_platform", input!);

    try {
      await expect(
        sendSuggestionOutcomeEmail(suggestion, "approved", {
          EMAIL_FROM: "wat@example.com",
          EMAIL_SERVER: smtp.url,
          WAT_EMAIL_NOTIFICATIONS: "1"
        })
      ).resolves.toMatchObject({ event: "suggestion.approved", to: "platform@example.com" });
      expect(getEmailOutbox()).toHaveLength(1);
      expect(smtp.messages[0]).toContain("To: platform@example.com");
      expect(smtp.messages[0]).toContain("Subject: wat suggestion approved");
    } finally {
      await smtp.close();
      resetEmailOutboxForTest();
      resetSuggestedEditsForTest();
    }
  });

  it("does not send email when disabled", async () => {
    resetEmailOutboxForTest();
    resetSuggestedEditsForTest();
    const input = validateSuggestedEntry({
      domains: ["web"],
      expansion: "Document Object Model",
      meaning: "Browser document tree API.",
      source_url: "https://example.com/dom",
      term: "DOM"
    });
    const suggestion = await submitNewEntrySuggestion("team_1", "user_platform", input!);

    await expect(sendSuggestionOutcomeEmail(suggestion, "rejected", {})).resolves.toBeNull();
    expect(getEmailOutbox()).toHaveLength(0);
    resetSuggestedEditsForTest();
  });
});
