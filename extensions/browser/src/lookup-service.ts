import {
  getCachedLookup,
  lookupCacheKey,
  putCachedLookup,
  type LookupCacheEntry
} from "./lookup-cache.js";
import { apiErrorFromResponse, apiErrorResult, offlineApiError } from "./api-errors.js";
import { type LookupMessage, type LookupResponse } from "./messages.js";
import { loadWatOptions, type WatOptions } from "./options.js";

interface LookupServiceDeps {
  fetchLookup?: (message: LookupMessage, options: WatOptions) => Promise<unknown>;
  getCachedLookup?: (key: string) => Promise<LookupCacheEntry | null>;
  loadOptions?: () => Promise<WatOptions>;
  putCachedLookup?: (key: string, entry: LookupCacheEntry) => Promise<void>;
}

export function boundedLimit(limit: number | undefined): string {
  if (!limit || !Number.isInteger(limit)) return "5";
  return Math.min(Math.max(limit, 1), 10).toString();
}

export function authHeaders(options: WatOptions): Headers {
  const headers = new Headers();
  if (options.apiToken) {
    headers.set("authorization", `Bearer ${options.apiToken}`);
  }
  if (options.accountEmail) {
    headers.set("x-wat-user-id", options.accountEmail);
  }
  if (options.teamId) {
    headers.set("x-wat-team-id", options.teamId);
  }

  return headers;
}

export async function fetchLookup(message: LookupMessage, options: WatOptions): Promise<unknown> {
  const url = new URL("/api/v1/search", options.apiBaseUrl);
  url.searchParams.set("q", message.term.trim());
  url.searchParams.set("limit", boundedLimit(message.limit));
  if (message.context?.trim()) {
    url.searchParams.set("context", message.context.trim());
  }

  let response: Response;
  try {
    response = await fetch(url, { headers: authHeaders(options) });
  } catch {
    throw offlineApiError("lookup");
  }
  if (!response.ok) {
    throw await apiErrorFromResponse("lookup", response);
  }

  return response.json() as Promise<unknown>;
}

export function cacheEntry(message: LookupMessage, body: unknown): LookupCacheEntry {
  return {
    body,
    cachedAt: new Date().toISOString(),
    context: message.context?.trim() ?? "",
    term: message.term.trim()
  };
}

export async function handleLookup(
  message: LookupMessage,
  deps: LookupServiceDeps = {}
): Promise<LookupResponse> {
  const load = deps.loadOptions ?? loadWatOptions;
  const readCache = deps.getCachedLookup ?? getCachedLookup;
  const writeCache = deps.putCachedLookup ?? putCachedLookup;
  const requestLookup = deps.fetchLookup ?? fetchLookup;

  const options = await load();
  const context = message.context?.trim() ?? "";
  const key = lookupCacheKey(options.apiBaseUrl, message.term, context);
  const cached = await readCache(key);

  try {
    const body = await requestLookup(message, options);
    await writeCache(key, cacheEntry(message, body));
    return { body, cached: false, ok: true };
  } catch (error) {
    if (cached) {
      return { body: cached.body, cached: true, ok: true };
    }

    return apiErrorResult(error, "lookup failed") as LookupResponse;
  }
}
