import { expect, test, chromium, type BrowserContext, type Worker } from "@playwright/test";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

const optionsStorageKey = "watOptions";
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
  response.setHeader("access-control-allow-methods", "GET, OPTIONS");
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

  if (url.pathname === "/api/v1/search") {
    if (request.headers.authorization === "Bearer bad-token") {
      response.writeHead(401, { "content-type": "application/json; charset=utf-8" });
      response.end(JSON.stringify({ error: "invalid_api_key" }));
      return;
    }

    response.writeHead(200, { "content-type": "application/json; charset=utf-8" });
    response.end(JSON.stringify(searchResponse(url.searchParams.get("q") ?? "")));
    return;
  }

  response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
  response.end("not found");
}

function searchResponse(query: string) {
  const term = query.trim().toUpperCase();
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
