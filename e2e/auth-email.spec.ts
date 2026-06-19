import { expect, test, type APIRequestContext } from "@playwright/test";

const mailpitUrl = process.env.MAILPIT_HTTP_URL ?? "http://127.0.0.1:8025";

test("email magic-link login works with Mailpit", async ({ page, request }) => {
  const email = `auth-${Date.now()}@example.com`;

  await page.goto("/login?next=/");
  await page.getByLabel("Email").fill(email);
  await page.getByRole("button", { name: "Send magic link" }).click();
  await expect(page.getByText("Check your email for a sign-in link.")).toBeVisible();

  const magicLink = await waitForMagicLink(request, email);
  await page.goto(magicLink);

  await expect(page).toHaveURL(/\/$/);
  const session = (await (await page.request.get("/api/auth/session")).json()) as {
    user?: { email?: string };
  };
  expect(session.user?.email).toBe(email);
});

async function waitForMagicLink(request: APIRequestContext, email: string): Promise<string> {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    const messageId = await findMessageId(request, email);
    if (messageId) {
      const raw = await (await request.get(`${mailpitUrl}/api/v1/message/${messageId}/raw`)).text();
      const link = extractMagicLink(raw);
      if (link) return link;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`magic-link email not found for ${email}`);
}

async function findMessageId(
  request: APIRequestContext,
  email: string
): Promise<string | undefined> {
  const response = await request.get(`${mailpitUrl}/api/v1/messages`);
  const body = (await response.json()) as {
    messages?: MailpitMessage[];
  };
  const message = body.messages?.find((item) =>
    item.To.some((recipient) => recipient.Address === email)
  );
  return message?.ID;
}

function extractMagicLink(raw: string): string | null {
  const decoded = raw
    .replace(/=\r?\n/g, "")
    .replace(/=3D/g, "=")
    .replace(/&amp;/g, "&");
  return (
    decoded.match(/https?:\/\/[^\s"'<>]+\/api\/auth\/callback\/email\?[^\s"'<>]+/)?.[0] ?? null
  );
}

interface MailpitMessage {
  ID: string;
  To: Array<{ Address: string }>;
}
