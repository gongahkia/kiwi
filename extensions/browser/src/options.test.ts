import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  defaultOptions,
  loadWatOptions,
  managedOptionsFromPolicy,
  optionsStorageKey,
  testWatConnection
} from "./options.js";

describe("options privacy defaults", () => {
  function stubStorage(managedPolicy?: Record<string, unknown> | Error) {
    const store = new Map<string, unknown>();
    vi.stubGlobal("browser", {
      storage: {
        local: {
          get: async (key: string) => ({ [key]: store.get(key) }),
          set: async (value: Record<string, unknown>) => {
            for (const [key, item] of Object.entries(value)) store.set(key, item);
          }
        },
        ...(managedPolicy
          ? {
              managed: {
                get: async () => {
                  if (managedPolicy instanceof Error) throw managedPolicy;
                  return managedPolicy;
                }
              }
            }
          : {})
      }
    });
  }

  beforeEach(() => {
    stubStorage();
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

  it("lets managed policy override local extension options", async () => {
    stubStorage({
      apiBaseUrl: "https://wat.example.test",
      domainFilters: ["Docs.Example.test", "docs.example.test", " "],
      highlightMode: true,
      hoverMode: false,
      teamId: "team_managed"
    });

    await browser.storage.local.set({
      [optionsStorageKey]: {
        apiBaseUrl: "https://local.example.test",
        domainFilters: ["local.example.test"],
        highlightMode: false,
        hoverMode: true,
        teamId: "team_local"
      }
    });

    expect(await loadWatOptions()).toMatchObject({
      apiBaseUrl: "https://wat.example.test",
      domainFilters: ["docs.example.test"],
      highlightMode: true,
      hoverMode: false,
      teamId: "team_managed"
    });
  });

  it("ignores unavailable managed storage", async () => {
    stubStorage(new Error("managed storage unavailable"));

    await browser.storage.local.set({
      [optionsStorageKey]: { apiBaseUrl: "https://local.example.test" }
    });

    expect(await loadWatOptions()).toMatchObject({
      apiBaseUrl: "https://local.example.test"
    });
  });

  it("sanitizes managed policy values", () => {
    expect(
      managedOptionsFromPolicy({
        apiBaseUrl: " https://wat.example.test ",
        domainFilters: [" Docs.Example.test ", "", 42, "docs.example.test"],
        highlightMode: "true",
        hoverMode: true,
        teamId: " team_1 "
      })
    ).toEqual({
      apiBaseUrl: "https://wat.example.test",
      domainFilters: ["docs.example.test"],
      hoverMode: true,
      teamId: "team_1"
    });
  });

  it("fails connection testing for invalid API URLs", async () => {
    await expect(
      testWatConnection({ ...defaultOptions, apiBaseUrl: "not a url" })
    ).resolves.toEqual({
      message: "Connection failed: invalid API base URL.",
      ok: false
    });
  });

  it("fails connection testing for unauthorized tokens", async () => {
    const fetchLookup = vi.fn().mockResolvedValue({
      json: async () => ({ error: "invalid_api_key" }),
      ok: false,
      status: 401
    });

    await expect(
      testWatConnection({ ...defaultOptions, apiToken: "bad-token" }, fetchLookup)
    ).resolves.toEqual({
      message: "Connection failed: unauthorized API token.",
      ok: false
    });
  });

  it("fails connection testing for unreachable APIs", async () => {
    const fetchLookup = vi.fn().mockRejectedValue(new Error("offline"));

    await expect(testWatConnection(defaultOptions, fetchLookup)).resolves.toEqual({
      message: "Connection failed: API is unreachable.",
      ok: false
    });
  });

  it("fails connection testing for unexpected API responses", async () => {
    const fetchLookup = vi.fn().mockResolvedValue({
      json: async () => ({ ok: true }),
      ok: true,
      status: 200
    });

    await expect(testWatConnection(defaultOptions, fetchLookup)).resolves.toEqual({
      message: "Connection failed: unexpected API response.",
      ok: false
    });
  });

  it("passes connection testing and sends configured auth headers", async () => {
    const fetchLookup = vi.fn().mockResolvedValue({
      json: async () => ({ matches: [] }),
      ok: true,
      status: 200
    });

    await expect(
      testWatConnection(
        {
          ...defaultOptions,
          accountEmail: "user@example.test",
          apiBaseUrl: "https://wat.example.test/root",
          apiToken: "test-token",
          teamId: "team_1"
        },
        fetchLookup
      )
    ).resolves.toEqual({
      message: "Connection verified. Saved.",
      ok: true
    });

    const [url, init] = fetchLookup.mock.calls[0]!;
    expect(url.toString()).toBe("https://wat.example.test/api/v1/search?q=API&limit=1");
    expect(init.headers.get("authorization")).toBe("Bearer test-token");
    expect(init.headers.get("x-wat-user-id")).toBe("user@example.test");
    expect(init.headers.get("x-wat-team-id")).toBe("team_1");
  });
});
