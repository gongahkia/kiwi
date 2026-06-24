import { expect, test, type Page } from "@playwright/test";

async function gotoHome(page: Page, query = "") {
  await page.goto(query ? `/?q=${encodeURIComponent(query)}` : "/");
}

async function fillSearch(page: Page, query: string) {
  await page.getByRole("searchbox", { name: "Search" }).fill(query);
}

function resultFor(page: Page, term: string) {
  return page.locator("article").filter({ has: page.getByRole("link", { name: term }) });
}

async function stubClipboard(page: Page) {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: {
        writeText: async (text: string) => {
          window.sessionStorage.setItem("copied-text", text);
        }
      }
    });
  });
}

test("loads the empty search shell", async ({ page }) => {
  await gotoHome(page);

  await expect(page.getByRole("heading", { name: "wat" })).toBeVisible();
  await expect(page.getByRole("searchbox", { name: "Search" })).toBeFocused();
  await expect(page.locator("article")).toHaveCount(0);
});

test("searches API and renders its top result", async ({ page }) => {
  await gotoHome(page);
  await fillSearch(page, "API");

  const api = resultFor(page, "API");
  await expect(api).toBeVisible();
  await expect(api).toContainText("Application Programming Interface");
  await expect(api).toContainText("web");
});

test("preloads search results from the q query parameter", async ({ page }) => {
  await gotoHome(page, "TLS");

  await expect(page.getByRole("searchbox", { name: "Search" })).toHaveValue("TLS");
  await expect(
    page.locator("article").filter({ hasText: "Transport Layer Security" })
  ).toBeVisible();
});

test("renders search UI from RSC data without the client search API", async ({ page }) => {
  await page.route("**/api/v1/search**", (route) => route.abort());
  await gotoHome(page, "API");

  await expect(resultFor(page, "API")).toBeVisible();
});

test("shows typed search results within 200ms after RSC data loads", async ({ page }) => {
  await gotoHome(page, "API");
  await expect(resultFor(page, "API")).toBeVisible();

  const search = page.getByRole("searchbox", { name: "Search" });
  const startedAt = await page.evaluate(() => performance.now());
  await search.fill("TLS");
  await page.waitForFunction(() => document.body.textContent?.includes("Transport Layer Security"));
  const elapsedMs = await page.evaluate((start) => performance.now() - start, startedAt);

  expect(elapsedMs).toBeLessThan(200);
});

test("shows an empty state for unmatched queries", async ({ page }) => {
  await gotoHome(page);
  await fillSearch(page, "zzzz-no-match");

  await expect(page.getByText("No results.")).toBeVisible();
});

test("opens create and suggest flows from unmatched queries", async ({ context, page }) => {
  await context.addCookies([
    {
      name: "wat_session",
      url: "http://127.0.0.1:3100",
      value: "user_admin"
    }
  ]);
  await gotoHome(page);
  await fillSearch(page, "zzzz-no-match");

  await page.getByRole("link", { name: "Save personal entry" }).click();

  await expect(page).toHaveURL(/\/personal\?term=zzzz-no-match$/);
  await expect(page.getByPlaceholder("term")).toHaveValue("zzzz-no-match");
  await expect(page.getByText("Generated ID: personal-zzzz-no-match")).toBeVisible();

  await gotoHome(page);
  await fillSearch(page, "zzzz-no-match");
  await page.getByRole("link", { name: "Suggest for review" }).click();

  await expect(page).toHaveURL(/\/suggest\?term=zzzz-no-match$/);
  await expect(page.getByPlaceholder("term")).toHaveValue("zzzz-no-match");
});

test("creates a personal entry without requiring a manual id", async ({ context, page }) => {
  await context.addCookies([
    {
      name: "wat_session",
      url: "http://127.0.0.1:3100",
      value: "user_generated_id"
    }
  ]);
  await page.goto("/personal");

  await expect(page.getByPlaceholder("id")).toHaveCount(0);
  await page.getByPlaceholder("term").fill("Queue Depth");
  await page.getByPlaceholder("expansion").fill("Quality of Service");
  await page.getByPlaceholder("meaning").fill("Internal queue health shorthand.");

  await expect(
    page.getByText("Generated ID: personal-queue-depth-quality-of-service")
  ).toBeVisible();
  await page.getByRole("button", { name: "Create entry" }).click();

  await expect(page.locator("article").filter({ hasText: "Queue Depth" })).toContainText(
    "Quality of Service"
  );
});

test("filters search results by domain", async ({ page }) => {
  await gotoHome(page);
  await fillSearch(page, "API");
  await expect(resultFor(page, "API")).toBeVisible();

  await page.getByLabel("Domain filter").selectOption("software");

  await expect(resultFor(page, "API")).toBeVisible();
  await expect(resultFor(page, "CRD")).toHaveCount(0);
  await expect(resultFor(page, "WebRTC")).toHaveCount(0);
});

test("can include low-confidence T3 and T4 results", async ({ page }) => {
  await gotoHome(page);
  await fillSearch(page, "Change Advisory Process");
  const lowConfidenceCap = resultFor(page, "CAP").filter({ hasText: "Change Advisory Process" });

  await expect(lowConfidenceCap).toHaveCount(0);

  await page.getByLabel("Show T3/T4").check();

  await expect(lowConfidenceCap).toContainText("Change Advisory Process");
});

test("navigates to the highlighted result with keyboard controls", async ({ page }) => {
  await gotoHome(page);
  const search = page.getByRole("searchbox", { name: "Search" });
  await search.fill("API");
  await expect(resultFor(page, "API")).toBeVisible();

  await search.press("ArrowDown");
  await search.press("Enter");

  await expect(page).toHaveURL(/\/term\/seed-api-application-programming-interface$/);
  await expect(page.getByRole("heading", { name: "API" })).toBeVisible();
});

test("copies a result citation", async ({ page }) => {
  await stubClipboard(page);
  await gotoHome(page);
  await fillSearch(page, "API");

  await resultFor(page, "API").getByLabel("Copy citation").click();

  await expect(resultFor(page, "API").getByLabel("Citation copied")).toBeVisible();
  await expect(
    page.evaluate(() => window.sessionStorage.getItem("copied-text"))
  ).resolves.toContain("Application Programming Interface");
});

test("search API returns JSON matches", async ({ request }) => {
  const response = await request.get("/api/v1/search?q=API&limit=1&min_confidence=T2");
  expect(response.ok()).toBe(true);

  const body = (await response.json()) as { matches: Array<{ entry: { term: string } }> };
  expect(body.matches[0]?.entry.term).toBe("API");
});

test("term page renders sources and copies share links", async ({ page }) => {
  await stubClipboard(page);
  await page.goto("/term/seed-api-application-programming-interface");

  await expect(page.getByRole("heading", { name: "API" })).toBeVisible();
  await expect(page.getByRole("link", { exact: true, name: "API" })).toBeVisible();

  await page.getByLabel("Copy share link").click();

  await expect(page.getByLabel("Share link copied")).toBeVisible();
  await expect(
    page.evaluate(() => window.sessionStorage.getItem("copied-text"))
  ).resolves.toContain("/term/seed-api-application-programming-interface");
});
