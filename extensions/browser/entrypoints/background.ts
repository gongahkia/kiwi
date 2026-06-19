import { defineBackground } from "wxt/utils/define-background";

import {
  getCachedLookup,
  lookupCacheKey,
  putCachedLookup,
  type LookupCacheEntry
} from "../src/lookup-cache.js";
import { isLookupMessage, type LookupMessage, type LookupResponse } from "../src/messages.js";
import {
  defaultOptions,
  loadWatOptions,
  optionsStorageKey,
  type WatOptions
} from "../src/options.js";

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

export default defineBackground(() => {
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
});
