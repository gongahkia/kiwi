import { expect, test, type APIRequestContext, type Page } from "@playwright/test";

const mailpitUrl = process.env.MAILPIT_HTTP_URL ?? "http://127.0.0.1:8025";

test("email magic-link login works with Mailpit and auto-joins same-domain users", async ({
  browser,
  page,
  request
}) => {
  const domain = `team-${Date.now()}.test`;
  const ownerEmail = `owner@${domain}`;
  const memberEmail = `member@${domain}`;

  const ownerSession = await signInWithEmail(page, request, ownerEmail);
  expect(ownerSession.user?.email).toBe(ownerEmail);
  expect(ownerSession.user?.role).toBe("admin");
  expect(ownerSession.user?.teamId).toContain(`team-${domain.replaceAll(".", "-")}-`);

  const memberContext = await browser.newContext();
  const memberPage = await memberContext.newPage();
  const memberSession = await signInWithEmail(memberPage, request, memberEmail);
  await memberContext.close();

  expect(memberSession.user?.email).toBe(memberEmail);
  expect(memberSession.user?.role).toBe("member");
  expect(memberSession.user?.teamId).toBe(ownerSession.user?.teamId);
});

async function signInWithEmail(
  page: Page,
  request: APIRequestContext,
  email: string
): Promise<AuthSession> {
  await page.goto("/login?next=/");
  await page.getByLabel("Email").fill(email);
  await page.getByRole("button", { name: "Send magic link" }).click();
  await expect(page.getByText("Check your email for a sign-in link.")).toBeVisible();

  const magicLink = await waitForMagicLink(request, email);
  await page.goto(magicLink);

  await expect(page).toHaveURL(/\/$/);
  return (await (await page.request.get("/api/auth/session")).json()) as AuthSession;
}

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

interface AuthSession {
  user?: {
    email?: string;
    role?: string | null;
    teamId?: string | null;
  };
}
