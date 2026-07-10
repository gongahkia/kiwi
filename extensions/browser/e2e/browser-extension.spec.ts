import { expect, test, chromium, type BrowserContext, type Worker } from "@playwright/test";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { readFileSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

const optionsStorageKey = "watOptions";
const sidePanelCustomEntryStorageKey = "watSidePanelCustomEntry";
const sidePanelQueryStorageKey = "watSidePanelQuery";
const extensionPath = path.resolve(process.cwd(), "extensions/browser/.output/chrome-mv3");

interface ExtensionRuntime {
  storage: {
    local: {
      get: (keys?: string | string[] | null) => Promise<Record<string, unknown>>;
      set: (items: Record<string, unknown>) => Promise<void> | void;
    };
  };
}

interface ExtensionSession {
  context: BrowserContext;
  extensionId: string;
  userDataDir: string;
  worker: Worker;
}

let server: Server;
let baseUrl: string;
let searchRequests: Array<{
  auth: string;
  context: string;
  limit: string;
  q: string;
  teamId: string;
  userId: string;
}> = [];
let customEntryRequests: Array<Record<string, unknown>> = [];
let savedCustomEntries: Array<{
  expansion: string;
  meaning: string;
  sourceTitle?: string;
  sourceUrl?: string;
  term: string;
}> = [];
const referenceTerms = [
  { id: "kubernetes", peers: ["Docker Swarm", "Nomad", "ECS"], term: "Kubernetes" },
  { id: "kafka", peers: ["RabbitMQ", "NATS", "Redpanda", "Pulsar"], term: "Kafka" },
  { id: "postgres", peers: ["MySQL", "MariaDB", "CockroachDB", "YugabyteDB"], term: "Postgres" },
  { id: "terraform", peers: ["Pulumi", "OpenTofu", "CloudFormation"], term: "Terraform" },
  {
    id: "datadog",
    peers: ["New Relic", "Grafana Cloud", "Honeycomb", "Splunk"],
    term: "Datadog"
  }
];
const referenceEntries = loadReferenceEntries();

test.beforeAll(async () => {
  server = createServer(handleRequest);
  await new Promise<void>((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address() as AddressInfo;
  baseUrl = `http://127.0.0.1:${address.port}`;
});

test.afterAll(async () => {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
});

test.beforeEach(() => {
  searchRequests = [];
  customEntryRequests = [];
  savedCustomEntries = [];
});

test("hover mode renders a sourced lookup tooltip", async () => {
  const session = await launchExtension();
  try {
    await setExtensionStorage(session.worker, {
      [optionsStorageKey]: {
        accountEmail: "",
        apiBaseUrl: baseUrl,
        apiToken: "",
        domainFilters: [],
        highlightMode: false,
        hoverMode: true
      }
    });

    const page = await session.context.newPage();
    await page.goto(`${baseUrl}/fixture`);
    await page.locator("#tls").hover();

    await expect(page.getByText("TLS: Transport Layer Security")).toBeVisible();
    await expect(page.getByText("A protocol for encrypted transport.")).toBeVisible();
    await expect(page.getByText("Alt: SSL, DTLS, HTTPS, +1 more")).toBeVisible();
    await expect(page.getByText("Mock TLS Source")).toBeVisible();
  } finally {
    await closeExtension(session);
  }
});

test("side panel renders alternatives for reference entries", async () => {
  const session = await launchExtension();
  try {
    await setExtensionStorage(session.worker, {
      [optionsStorageKey]: {
        accountEmail: "",
        apiBaseUrl: baseUrl,
        apiToken: "",
        domainFilters: [],
        highlightMode: false,
        hoverMode: false
      }
    });

    const page = await session.context.newPage();
    await page.goto(`chrome-extension://${session.extensionId}/sidepanel.html`);

    for (const reference of referenceTerms) {
      await page.locator("#query").fill(reference.term);
      await page.getByRole("button", { name: "Search" }).click();
      const result = page
        .locator("article")
        .filter({ hasText: `${reference.term} - ${reference.term}` });
      await expect(result).toBeVisible();
      await expect(result.getByText("Alternatives:")).toBeVisible();
      for (const peer of reference.peers) {
        await expect(result.getByRole("button", { name: peer })).toBeVisible();
      }
    }
  } finally {
    await closeExtension(session);
  }
});

test("fresh install does not send hover or highlight lookups before opt-in", async () => {
  const session = await launchExtension();
  try {
    const page = await session.context.newPage();
    await page.goto(`${baseUrl}/privacy-fixture`);
    await page.locator("#tls").hover();
    await page.waitForTimeout(350);

    expect(searchRequests).toEqual([]);
  } finally {
    await closeExtension(session);
  }
});

test("hover lookup sends token and bounded context without page body text", async () => {
  const session = await launchExtension();
  try {
    await setExtensionStorage(session.worker, {
      [optionsStorageKey]: {
        accountEmail: "",
        apiBaseUrl: baseUrl,
        apiToken: "",
        domainFilters: [],
        highlightMode: false,
        hoverMode: true
      }
    });

    const page = await session.context.newPage();
    await page.goto(`${baseUrl}/privacy-fixture`);
    await page.locator("#tls").hover();

    await expect(page.getByText("TLS: Transport Layer Security")).toBeVisible();
    await expect.poll(() => searchRequests.length).toBe(1);

    const request = searchRequests[0]!;
    expect(request).toMatchObject({ limit: "1", q: "TLS" });
    expect(request.context).toContain("127.0.0.1");
    expect(request.context).toContain("Private Ticket WAT");
    expect(request.context).toContain("Deployment Notes");
    expect(request.context).not.toContain("SECRET_FULL_PAGE_BODY");
    expect(request.context).not.toContain("Never send this paragraph");
  } finally {
    await closeExtension(session);
  }
});

test("side panel consumes queued lookup and renders results", async () => {
  const session = await launchExtension();
  try {
    await setExtensionStorage(session.worker, {
      [optionsStorageKey]: {
        accountEmail: "",
        apiBaseUrl: baseUrl,
        apiToken: "",
        domainFilters: [],
        highlightMode: false,
        hoverMode: false
      },
      [sidePanelQueryStorageKey]: {
        context: "docs.example.test",
        createdAt: new Date().toISOString(),
        term: "TLS"
      }
    });

    const page = await session.context.newPage();
    await page.goto(`chrome-extension://${session.extensionId}/sidepanel.html`);

    await expect(page.locator("#query")).toHaveValue("TLS");
    await expect(page.locator("#page-context")).toHaveText("docs.example.test");
    await expect(page.getByText("private/proprietary")).toBeVisible();
    await expect(page.getByText("TLS - Transport Layer Security")).toBeVisible();
    await expect(page.getByText("A protocol for encrypted transport.")).toBeVisible();
    await expect(page.getByText("Alternatives:")).toBeVisible();
    await page.getByRole("button", { name: "SSL" }).click();
    await expect(page.locator("#query")).toHaveValue("SSL");
    await expect(page.getByText("SSL - Secure Sockets Layer")).toBeVisible();
  } finally {
    await closeExtension(session);
  }
});

test("side panel previews queued custom entry source before saving", async () => {
  const session = await launchExtension();
  try {
    await setExtensionStorage(session.worker, {
      [optionsStorageKey]: {
        accountEmail: "",
        apiBaseUrl: baseUrl,
        apiToken: "",
        domainFilters: [],
        highlightMode: false,
        hoverMode: false
      },
      [sidePanelCustomEntryStorageKey]: {
        context: "docs.example.test",
        createdAt: new Date().toISOString(),
        sourceTitle: "TLS handbook",
        sourceUrl: "https://docs.example.test/tls",
        term: "TLS"
      }
    });

    const page = await session.context.newPage();
    await page.goto(`chrome-extension://${session.extensionId}/sidepanel.html`);

    await expect(page.locator("#save-term")).toHaveValue("TLS");
    await expect(page.locator("#save-source-preview")).toHaveText(
      "Source: TLS handbook - https://docs.example.test/tls"
    );
    await expect(page.locator("#save-status")).toHaveText("Ready to save from docs.example.test.");
  } finally {
    await closeExtension(session);
  }
});

test("side panel handles custom entry conflicts with update choices", async () => {
  const session = await launchExtension();
  try {
    await setExtensionStorage(session.worker, {
      [optionsStorageKey]: {
        accountEmail: "user@example.test",
        apiBaseUrl: baseUrl,
        apiToken: "test-token",
        domainFilters: [],
        highlightMode: false,
        hoverMode: false
      },
      [sidePanelCustomEntryStorageKey]: {
        context: "docs.example.test",
        createdAt: new Date().toISOString(),
        sourceTitle: "TLS handbook",
        sourceUrl: "https://docs.example.test/tls",
        term: "TLS"
      }
    });

    const page = await session.context.newPage();
    await page.goto(`chrome-extension://${session.extensionId}/sidepanel.html`);
    await page.locator("#save-expansion").fill("Transport Layer Security");
    await page.getByRole("button", { name: "Save acronym" }).click();

    await expect(page.locator("#save-status")).toHaveText(
      "TLS already exists. Update it, keep both, or cancel."
    );
    await expect(page.getByRole("button", { name: "Update existing" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Keep both" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Cancel" })).toBeVisible();

    await page.getByRole("button", { name: "Update existing" }).click();

    await expect(page.locator("#save-status")).toHaveText(
      "Saved. Future searches will include this custom layer."
    );
    expect(customEntryRequests).toHaveLength(2);
    expect(customEntryRequests[0]).toMatchObject({ mode: "create", term: "TLS" });
    expect(customEntryRequests[1]).toMatchObject({ mode: "upsert", term: "TLS" });
  } finally {
    await closeExtension(session);
  }
});

test("saves selected page text and finds it in a later lookup", async () => {
  const session = await launchExtension();
  try {
    await setExtensionStorage(session.worker, {
      [optionsStorageKey]: {
        accountEmail: "user@example.test",
        apiBaseUrl: baseUrl,
        apiToken: "test-token",
        domainFilters: [],
        highlightMode: false,
        hoverMode: false
      }
    });

    const fixture = await session.context.newPage();
    await fixture.goto(`${baseUrl}/custom-entry-fixture`);
    await fixture.locator("#custom-term").dblclick();
    const selectedTerm = await fixture.evaluate(() => window.getSelection()?.toString() ?? "");
    expect(selectedTerm).toBe("QDEPTH");

    await setExtensionStorage(session.worker, {
      [sidePanelCustomEntryStorageKey]: {
        context: "docs.example.test",
        createdAt: new Date().toISOString(),
        sourceTitle: "Queue handbook",
        sourceUrl: `${baseUrl}/custom-entry-fixture`,
        term: selectedTerm
      }
    });

    const sidePanel = await session.context.newPage();
    await sidePanel.goto(`chrome-extension://${session.extensionId}/sidepanel.html`);
    await expect(sidePanel.locator("#save-term")).toHaveValue("QDEPTH");

    await sidePanel.locator("#save-expansion").fill("Queue Depth");
    await sidePanel.locator("#save-meaning").fill("Internal queue backlog health shorthand.");
    await sidePanel.getByRole("button", { name: "Save acronym" }).click();

    await expect(sidePanel.locator("#save-status")).toHaveText(
      "Saved. Future searches will include this custom layer."
    );
    expect(customEntryRequests.at(-1)).toMatchObject({
      expansion: "Queue Depth",
      meaning: "Internal queue backlog health shorthand.",
      mode: "create",
      term: "QDEPTH"
    });

    await sidePanel.locator("#query").fill("QDEPTH");
    await sidePanel.getByRole("button", { name: "Search" }).click();

    const result = sidePanel.locator("article").filter({ hasText: "QDEPTH - Queue Depth" });
    await expect(result).toBeVisible();
    await expect(result).toContainText("Internal queue backlog health shorthand.");
    await expect(result).toContainText(`Queue handbook - ${baseUrl}/custom-entry-fixture`);
  } finally {
    await closeExtension(session);
  }
});

test("options page tests connection before saving settings", async () => {
  const session = await launchExtension();
  try {
    const page = await session.context.newPage();
    await page.goto(`chrome-extension://${session.extensionId}/options.html`);

    await page.locator("#api-base-url").fill(baseUrl);
    await page.locator("#account-email").fill("user@example.test");
    await page.locator("#api-token").fill("bad-token");
    await page.getByRole("button", { name: "Save" }).click();

    await expect(page.getByRole("status")).toHaveText("Connection failed: unauthorized API token.");
    await expect(
      readExtensionStorage<{ apiToken?: string }>(session.worker, optionsStorageKey)
    ).resolves.not.toMatchObject({ apiToken: "bad-token" });
  } finally {
    await closeExtension(session);
  }
});

test("options page saves active team picker and lookup uses that team", async () => {
  const session = await launchExtension();
  try {
    const page = await session.context.newPage();
    await page.goto(`chrome-extension://${session.extensionId}/options.html`);

    await page.locator("#api-base-url").fill(baseUrl);
    await page.locator("#account-email").fill("user@example.test");
    await page.locator("#api-token").fill("test-token");
    await page.locator("#team-id").fill("team-alpha");
    await page.getByRole("button", { name: "Add team" }).click();
    await page.locator("#team-id").fill("team-beta");
    await page.getByRole("button", { name: "Add team" }).click();
    await page.locator("#team-picker").selectOption("team-alpha");
    await page.getByRole("button", { name: "Save" }).click();

    await expect(page.getByRole("status")).toHaveText("Connection verified. Saved.");
    await expect(
      readExtensionStorage<{
        apiToken?: string;
        teamId?: string;
        teams?: Array<{ id: string; name: string }>;
      }>(session.worker, optionsStorageKey)
    ).resolves.toMatchObject({
      apiToken: "test-token",
      teamId: "team-alpha",
      teams: [
        { id: "team-alpha", name: "team-alpha" },
        { id: "team-beta", name: "team-beta" }
      ]
    });
    expect(searchRequests.at(-1)).toMatchObject({
      auth: "Bearer test-token",
      q: "API",
      teamId: "team-alpha",
      userId: "user@example.test"
    });

    const sidePanel = await session.context.newPage();
    await sidePanel.goto(`chrome-extension://${session.extensionId}/sidepanel.html`);
    await sidePanel.locator("#query").fill("TLS");
    await sidePanel.getByRole("button", { name: "Search" }).click();

    await expect(sidePanel.getByText("TLS - Transport Layer Security")).toBeVisible();
    expect(searchRequests.at(-1)).toMatchObject({
      auth: "Bearer test-token",
      q: "TLS",
      teamId: "team-alpha",
      userId: "user@example.test"
    });
  } finally {
    await closeExtension(session);
  }
});

async function launchExtension(): Promise<ExtensionSession> {
  const userDataDir = await mkdtemp(path.join(tmpdir(), "wat-ext-"));
  const context = await chromium.launchPersistentContext(userDataDir, {
    args: [`--disable-extensions-except=${extensionPath}`, `--load-extension=${extensionPath}`],
    channel: "chromium",
    headless: true
  });
  const worker =
    context.serviceWorkers()[0] ??
    (await context.waitForEvent("serviceworker", { timeout: 10000 }));
  const extensionId = worker.url().split("/")[2];
  if (!extensionId) throw new Error("extension id not found");
  await waitForExtensionInstall(worker);

  return { context, extensionId, userDataDir, worker };
}

async function closeExtension(session: ExtensionSession) {
  await session.context.close();
  await rm(session.userDataDir, { force: true, recursive: true });
}

async function setExtensionStorage(worker: Worker, items: Record<string, unknown>) {
  await worker.evaluate(async (values) => {
    const runtime = globalThis as typeof globalThis & {
      browser?: ExtensionRuntime;
      chrome?: ExtensionRuntime;
    };
    const api = runtime.browser ?? runtime.chrome;
    if (!api) throw new Error("extension storage api not found");
    await api.storage.local.set(values);
  }, items);
}

async function readExtensionStorage<T>(worker: Worker, key: string): Promise<T | undefined> {
  return worker.evaluate(async (storageKey) => {
    const runtime = globalThis as typeof globalThis & {
      browser?: ExtensionRuntime;
      chrome?: ExtensionRuntime;
    };
    const api = runtime.browser ?? runtime.chrome;
    if (!api) throw new Error("extension storage api not found");
    const stored = await api.storage.local.get(storageKey);
    return stored[storageKey] as T | undefined;
  }, key);
}

async function waitForExtensionInstall(worker: Worker) {
  await worker.evaluate(async () => {
    const runtime = globalThis as typeof globalThis & {
      browser?: ExtensionRuntime;
      chrome?: ExtensionRuntime;
    };
    const api = runtime.browser ?? runtime.chrome;
    if (!api) throw new Error("extension storage api not found");
    for (let attempt = 0; attempt < 50; attempt += 1) {
      const stored = await api.storage.local.get("watInstalledAt");
      if (stored.watInstalledAt) return;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new Error("extension install storage not initialized");
  });
}

function handleRequest(request: IncomingMessage, response: ServerResponse) {
  const url = new URL(request.url ?? "/", baseUrl || "http://127.0.0.1");
  response.setHeader("access-control-allow-origin", "*");
  response.setHeader("access-control-allow-methods", "GET, POST, OPTIONS");
  response.setHeader(
    "access-control-allow-headers",
    "authorization, content-type, x-wat-team-id, x-wat-user-id"
  );
  if (request.method === "OPTIONS") {
    response.writeHead(204);
    response.end();
    return;
  }

  if (url.pathname === "/fixture") {
    response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    response.end('<!doctype html><title>Docs</title><p>Use <span id="tls">TLS</span> here.</p>');
    return;
  }

  if (url.pathname === "/reference-fixture") {
    response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    response.end(
      `<!doctype html><title>Reference Docs</title><p>${referenceTerms
        .map((reference) => `<span id="${reference.id}">${reference.term}</span>`)
        .join(" ")}</p>`
    );
    return;
  }

  if (url.pathname === "/privacy-fixture") {
    response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    response.end(`<!doctype html>
      <title>Private Ticket WAT</title>
      <h1>Deployment Notes</h1>
      <p><span id="tls">TLS</span> protects traffic.</p>
      <p>Never send this paragraph SECRET_FULL_PAGE_BODY to the lookup API.</p>`);
    return;
  }

  if (url.pathname === "/custom-entry-fixture") {
    response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    response.end(
      '<!doctype html><title>Queue handbook</title><p>Select <span id="custom-term">QDEPTH</span> before saving.</p>'
    );
    return;
  }

  if (url.pathname === "/api/v1/search") {
    searchRequests.push({
      auth: request.headers.authorization ?? "",
      context: url.searchParams.get("context") ?? "",
      limit: url.searchParams.get("limit") ?? "",
      q: url.searchParams.get("q") ?? "",
      teamId: headerValue(request.headers["x-wat-team-id"]),
      userId: headerValue(request.headers["x-wat-user-id"])
    });

    if (request.headers.authorization === "Bearer bad-token") {
      response.writeHead(401, { "content-type": "application/json; charset=utf-8" });
      response.end(JSON.stringify({ error: "invalid_api_key" }));
      return;
    }

    response.writeHead(200, { "content-type": "application/json; charset=utf-8" });
    response.end(JSON.stringify(searchResponse(url.searchParams.get("q") ?? "")));
    return;
  }

  if (url.pathname === "/api/v1/custom-entries" && request.method === "POST") {
    void readJsonBody(request).then((body) => {
      customEntryRequests.push(body);
      if (
        body.term !== "TLS" &&
        typeof body.term === "string" &&
        typeof body.expansion === "string"
      ) {
        savedCustomEntries.push({
          expansion: body.expansion,
          meaning: typeof body.meaning === "string" ? body.meaning : "",
          sourceTitle: typeof body.sourceTitle === "string" ? body.sourceTitle : undefined,
          sourceUrl: typeof body.sourceUrl === "string" ? body.sourceUrl : undefined,
          term: body.term
        });
        response.writeHead(200, { "content-type": "application/json; charset=utf-8" });
        response.end(JSON.stringify({ entry: { term: body.term }, mode: "created" }));
        return;
      }
      if (body.mode === "upsert") {
        response.writeHead(200, { "content-type": "application/json; charset=utf-8" });
        response.end(JSON.stringify({ entry: { term: body.term }, mode: "updated" }));
        return;
      }

      response.writeHead(409, { "content-type": "application/json; charset=utf-8" });
      response.end(JSON.stringify({ error: "personal entry already exists" }));
    });
    return;
  }

  response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
  response.end("not found");
}

function headerValue(value: string | string[] | undefined): string {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

async function readJsonBody(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }

  return JSON.parse(Buffer.concat(chunks).toString("utf8")) as Record<string, unknown>;
}

function searchResponse(query: string) {
  const trimmed = query.trim();
  const saved = savedCustomEntries.find(
    (entry) => entry.term.toLowerCase() === trimmed.toLowerCase()
  );
  if (saved) {
    return {
      matches: [
        {
          entry: {
            expansions: [saved.expansion],
            meaning_short: saved.meaning,
            sources: saved.sourceUrl
              ? [
                  {
                    title: saved.sourceTitle,
                    url: saved.sourceUrl
                  }
                ]
              : [],
            term: saved.term
          }
        }
      ]
    };
  }

  const reference = referenceEntries.get(trimmed.toLowerCase());
  if (reference) {
    return {
      matches: [
        {
          entry: {
            contemporaries: reference.contemporaries,
            expansions: reference.expansions,
            meaning_short: reference.meaning_short,
            sources: reference.sources.map((source) => ({ title: source.title, url: source.url })),
            term: reference.term
          }
        }
      ]
    };
  }

  const term = trimmed.toUpperCase();
  if (term === "SSL") {
    return {
      matches: [
        {
          entry: {
            expansions: ["Secure Sockets Layer"],
            meaning_short: "An older transport encryption protocol.",
            sources: [],
            term: "SSL"
          }
        }
      ]
    };
  }
  if (term !== "TLS") return { matches: [] };

  return {
    matches: [
      {
        entry: {
          contemporaries: ["SSL", "DTLS", "HTTPS", "QUIC"],
          expansions: ["Transport Layer Security"],
          meaning_short: "A protocol for encrypted transport.",
          sources: [
            {
              title: "Mock TLS Source",
              url: "https://example.test/tls"
            }
          ],
          term: "TLS"
        }
      }
    ]
  };
}

function loadReferenceEntries(): Map<
  string,
  {
    contemporaries: string[];
    expansions: string[];
    meaning_short: string;
    sources: Array<{ title: string; url: string }>;
    term: string;
  }
> {
  const file = path.resolve(process.cwd(), "data/deltas/2026-06-23/contemporaries-seed.json");
  const corpus = JSON.parse(readFileSync(file, "utf8")) as {
    entries: Array<{
      contemporaries: string[];
      expansions: string[];
      meaning_short: string;
      sources: Array<{ title: string; url: string }>;
      term: string;
    }>;
  };
  return new Map(corpus.entries.map((entry) => [entry.term.toLowerCase(), entry]));
}
