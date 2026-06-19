import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  getCachedLookup,
  lookupCacheStorageKey,
  putCachedLookup,
  type LookupCacheEntry
} from "./lookup-cache.js";
import { handleLookup } from "./lookup-service.js";
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

describe("lookup service", () => {
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
