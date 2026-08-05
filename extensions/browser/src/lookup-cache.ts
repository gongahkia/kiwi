export interface LookupCacheEntry {
  body: unknown;
  cachedAt: string;
  context: string;
  term: string;
}

type LookupCache = Record<string, LookupCacheEntry>;

export const lookupCacheStorageKey = "watLookupCache";

export function lookupCacheKey(apiBaseUrl: string, term: string, context = ""): string {
  return [apiBaseUrl.replace(/\/$/, ""), term.trim().toLowerCase(), context.trim()].join("\n");
}

async function readCache(): Promise<LookupCache> {
  const stored = (await browser.storage.local.get(lookupCacheStorageKey)) as Record<
    string,
    LookupCache | undefined
  >;
  return stored[lookupCacheStorageKey] ?? {};
}

export async function getCachedLookup(key: string): Promise<LookupCacheEntry | null> {
  const cache = await readCache();
  return cache[key] ?? null;
}

export async function putCachedLookup(key: string, entry: LookupCacheEntry, limit = 500) {
  const cache = await readCache();
  cache[key] = entry;

  const bounded = Object.fromEntries(
    Object.entries(cache)
      .sort(([, left], [, right]) => right.cachedAt.localeCompare(left.cachedAt))
      .slice(0, limit)
  );

  await browser.storage.local.set({ [lookupCacheStorageKey]: bounded });
}
