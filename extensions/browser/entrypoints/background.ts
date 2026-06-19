import { defineBackground } from "wxt/utils/define-background";

import {
  getCachedLookup,
  lookupCacheKey,
  putCachedLookup,
  type LookupCacheEntry
} from "../src/lookup-cache.js";
import {
  isLookupMessage,
  sidePanelQueryStorageKey,
  type LookupMessage,
  type LookupResponse,
  type SidePanelQuery
} from "../src/messages.js";
import {
  defaultOptions,
  loadWatOptions,
  optionsStorageKey,
  type WatOptions
} from "../src/options.js";

type BrowserTab = Awaited<ReturnType<typeof browser.tabs.query>>[number];
interface ContextMenuClickInfo {
  menuItemId: number | string;
  selectionText?: string;
}

const contextMenuId = "wat.lookup.selection";

function boundedLimit(limit: number | undefined): string {
  if (!limit || !Number.isInteger(limit)) return "5";
  return Math.min(Math.max(limit, 1), 10).toString();
}

function authHeaders(options: WatOptions): Headers {
  const headers = new Headers();
  if (options.apiToken) {
    headers.set("authorization", `Bearer ${options.apiToken}`);
  }
  if (options.accountEmail) {
    headers.set("x-wat-user-id", options.accountEmail);
  }

  return headers;
}

async function fetchLookup(message: LookupMessage, options: WatOptions): Promise<unknown> {
  const url = new URL("/api/v1/search", options.apiBaseUrl);
  url.searchParams.set("q", message.term.trim());
  url.searchParams.set("limit", boundedLimit(message.limit));
  if (message.context?.trim()) {
    url.searchParams.set("context", message.context.trim());
  }

  const response = await fetch(url, { headers: authHeaders(options) });
  if (!response.ok) {
    throw new Error(`lookup failed: ${response.status}`);
  }

  return response.json() as Promise<unknown>;
}

function cacheEntry(message: LookupMessage, body: unknown): LookupCacheEntry {
  return {
    body,
    cachedAt: new Date().toISOString(),
    context: message.context?.trim() ?? "",
    term: message.term.trim()
  };
}

async function handleLookup(message: LookupMessage): Promise<LookupResponse> {
  const options = await loadWatOptions();
  const context = message.context?.trim() ?? "";
  const key = lookupCacheKey(options.apiBaseUrl, message.term, context);
  const cached = await getCachedLookup(key);

  try {
    const body = await fetchLookup(message, options);
    await putCachedLookup(key, cacheEntry(message, body));
    return { body, cached: false, ok: true };
  } catch (error) {
    if (cached) {
      return { body: cached.body, cached: true, ok: true };
    }

    return {
      error: error instanceof Error ? error.message : "lookup failed",
      ok: false
    };
  }
}

function tabContext(tab: BrowserTab): string {
  if (!tab.url) return "";
  try {
    const url = new URL(tab.url);
    return url.hostname || tab.url;
  } catch {
    return tab.url;
  }
}

function openSidePanel(tab: BrowserTab) {
  if (tab.id == null || !browser.sidePanel) return;
  void browser.sidePanel.open({ tabId: tab.id });
}

function ensureContextMenu() {
  void browser.contextMenus.removeAll().then(() => {
    browser.contextMenus.create({
      contexts: ["selection"],
      id: contextMenuId,
      title: 'Look up "%s" in wat'
    });
  });
}

async function queueSidePanelLookup(tab: BrowserTab, term: string) {
  const query: SidePanelQuery = {
    context: tabContext(tab),
    createdAt: new Date().toISOString(),
    term: term.trim()
  };

  await browser.storage.local.set({ [sidePanelQueryStorageKey]: query });
  openSidePanel(tab);
}

export default defineBackground(() => {
  ensureContextMenu();

  browser.runtime.onInstalled.addListener(() => {
    void browser.storage.local.get(optionsStorageKey).then((stored: Record<string, unknown>) => {
      if (!stored[optionsStorageKey]) {
        void browser.storage.local.set({ [optionsStorageKey]: defaultOptions });
      }
    });
    void browser.storage.local.set({ watInstalledAt: new Date().toISOString() });
  });

  browser.runtime.onMessage.addListener((message: unknown) => {
    if (!isLookupMessage(message)) return undefined;
    return handleLookup(message);
  });

  browser.contextMenus.onClicked.addListener((info: ContextMenuClickInfo, tab?: BrowserTab) => {
    if (info.menuItemId !== contextMenuId || !info.selectionText?.trim() || !tab) return;
    void queueSidePanelLookup(tab, info.selectionText);
  });

  browser.action.onClicked.addListener((tab: BrowserTab) => {
    openSidePanel(tab);
  });
});
