import { beforeEach, describe, expect, it, vi } from "vitest";

import { defaultOptions, loadWatOptions, optionsStorageKey } from "./options.js";

describe("options privacy defaults", () => {
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

  it("fresh install disables automatic lookup modes", async () => {
    expect(await loadWatOptions()).toEqual(defaultOptions);
    expect(defaultOptions).toMatchObject({
      accountEmail: "",
      apiToken: "",
      highlightMode: false,
      hoverMode: false
    });
  });

  it("keeps stored opt-in lookup modes explicit", async () => {
    await browser.storage.local.set({
      [optionsStorageKey]: { highlightMode: true, hoverMode: true }
    });

    expect(await loadWatOptions()).toMatchObject({
      highlightMode: true,
      hoverMode: true
    });
  });
});
