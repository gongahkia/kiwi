import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  getCachedLookup,
  lookupCacheStorageKey,
  putCachedLookup,
  type LookupCacheEntry
} from "./lookup-cache.js";
import { fetchLookup, handleLookup } from "./lookup-service.js";
import type { LookupMessage } from "./messages.js";
import { defaultOptions } from "./options.js";

const message: LookupMessage = {
  context: "kubernetes autoscaling",
  limit: 1,
  term: "CAP",
  type: "wat.lookup"
};

function entry(index: number): LookupCacheEntry {
  return {
    body: { index },
    cachedAt: new Date(index * 1000).toISOString(),
    context: "",
    term: `TERM${index}`
  };
}

function jsonResponse(status: number, body: unknown = {}, headers?: HeadersInit): Response {
  return new Response(JSON.stringify(body), { headers, status });
}

describe("lookup service", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  beforeEach(() => {
    const store = new Map<string, unknown>();
    vi.stubGlobal("browser", {
      storage: {
        local: {
          get: async (key: string) => ({ [key]: store.get(key) }),
          set: async (value: Record<string, unknown>) => {
            for (const [key, item] of Object.entries(value)) store.set(key, item);
          }
        }
      }
    });
  });

  it("returns cached lookup when fetch fails offline", async () => {
    const cached: LookupCacheEntry = {
      body: { matches: [{ entry: { id: "team-example-cap" } }] },
      cachedAt: "2026-06-19T00:00:00.000Z",
      context: message.context ?? "",
      term: message.term
    };

    await expect(
      handleLookup(message, {
        fetchLookup: async () => {
          throw new Error("offline");
        },
        getCachedLookup: async () => cached,
        loadOptions: async () => ({ ...defaultOptions, apiBaseUrl: "https://wat.test" })
      })
    ).resolves.toEqual({ body: cached.body, cached: true, ok: true });
  });

  it("classifies failed lookup states", async () => {
    const cases = [
      {
        expected: {
          error: "lookup failed: validation error: invalid query",
          ok: false,
          status: 400
        },
        response: jsonResponse(400, { error: "invalid query" })
      },
      {
        expected: {
          error: "lookup failed: unauthorized. Check API token.",
          ok: false,
          status: 401
        },
        response: jsonResponse(401, { error: "invalid_api_key" })
      },
      {
        expected: {
          error: "lookup failed: forbidden. Check account or team access.",
          ok: false,
          status: 403
        },
        response: jsonResponse(403, { error: "team_required" })
      },
      {
        expected: {
          error: "lookup failed: rate-limited. Retry after 30s.",
          ok: false,
          status: 429
        },
        response: jsonResponse(429, { error: "rate_limited" }, { "retry-after": "30" })
      }
    ];

    for (const testCase of cases) {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(testCase.response));

      await expect(
        handleLookup(message, {
          fetchLookup,
          getCachedLookup: async () => null,
          loadOptions: async () => ({ ...defaultOptions, apiBaseUrl: "https://wat.test" })
        })
      ).resolves.toEqual(testCase.expected);
    }
  });

  it("classifies uncached offline lookup failures", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")));

    await expect(
      handleLookup(message, {
        fetchLookup,
        getCachedLookup: async () => null,
        loadOptions: async () => ({ ...defaultOptions, apiBaseUrl: "https://wat.test" })
      })
    ).resolves.toEqual({ error: "lookup failed: offline or API unreachable.", ok: false });
  });

  it("keeps only the latest 500 cached lookups", async () => {
    for (let index = 0; index < 505; index += 1) {
      await putCachedLookup(`key-${index}`, entry(index));
    }

    expect(await getCachedLookup("key-0")).toBeNull();
    expect(await getCachedLookup("key-504")).toMatchObject({ term: "TERM504" });
    const stored = (await browser.storage.local.get(lookupCacheStorageKey)) as Record<
      string,
      Record<string, LookupCacheEntry>
    >;
    expect(Object.keys(stored[lookupCacheStorageKey] ?? {})).toHaveLength(500);
  });
});
