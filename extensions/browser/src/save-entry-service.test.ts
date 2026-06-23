import { afterEach, describe, expect, it, vi } from "vitest";

import {
  fetchSaveCustomEntry,
  handleSaveCustomEntry,
  saveCustomEntryPayload
} from "./save-entry-service.js";
import type { SaveCustomEntryMessage } from "./messages.js";
import { defaultOptions } from "./options.js";

const message: SaveCustomEntryMessage = {
  domains: ["Docs.Example.test", "docs.example.test"],
  expansion: "Transport Layer Security",
  meaning: "Encrypted transport.",
  scope: "personal",
  sourceTitle: "Docs",
  sourceUrl: "https://docs.example.test/tls",
  term: "TLS",
  type: "wat.customEntry.save"
};

function jsonResponse(status: number, body: unknown = {}, headers?: HeadersInit): Response {
  return new Response(JSON.stringify(body), { headers, status });
}

describe("save custom entry service", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("normalizes payloads for the API", () => {
    expect(saveCustomEntryPayload(message)).toEqual({
      domains: ["docs.example.test"],
      expansion: "Transport Layer Security",
      meaning: "Encrypted transport.",
      scope: "personal",
      sourceTitle: "Docs",
      sourceUrl: "https://docs.example.test/tls",
      term: "TLS"
    });
  });

  it("requires term and expansion before calling the API", async () => {
    await expect(
      handleSaveCustomEntry(
        { ...message, expansion: " " },
        {
          fetchSaveCustomEntry: async () => {
            throw new Error("should not be called");
          }
        }
      )
    ).resolves.toEqual({ error: "term and expansion are required", ok: false });
  });

  it("returns API save responses", async () => {
    await expect(
      handleSaveCustomEntry(message, {
        fetchSaveCustomEntry: async (input) => ({ entry: { term: input.term } }),
        loadOptions: async () => ({ ...defaultOptions, apiBaseUrl: "https://wat.test" })
      })
    ).resolves.toEqual({ body: { entry: { term: "TLS" } }, ok: true });
  });

  it("classifies failed save states", async () => {
    const cases = [
      {
        expected: {
          error: "save failed: validation error: term, expansion, and valid mode are required",
          ok: false,
          status: 400
        },
        response: jsonResponse(400, { error: "term, expansion, and valid mode are required" })
      },
      {
        expected: { error: "save failed: unauthorized. Check API token.", ok: false, status: 401 },
        response: jsonResponse(401, { error: "api token and x-wat-user-id are required" })
      },
      {
        expected: {
          error: "save failed: forbidden. Check account or team access.",
          ok: false,
          status: 403
        },
        response: jsonResponse(403, { error: "x-wat-team-id is required for team entries" })
      },
      {
        expected: {
          error: "save failed: rate-limited. Retry after 15s.",
          ok: false,
          status: 429
        },
        response: jsonResponse(429, { error: "rate_limited", retry_after: 15 })
      }
    ];

    for (const testCase of cases) {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(testCase.response));

      await expect(
        handleSaveCustomEntry(message, {
          fetchSaveCustomEntry,
          loadOptions: async () => ({ ...defaultOptions, apiBaseUrl: "https://wat.test" })
        })
      ).resolves.toEqual(testCase.expected);
    }
  });

  it("classifies offline save failures", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")));

    await expect(
      handleSaveCustomEntry(message, {
        fetchSaveCustomEntry,
        loadOptions: async () => ({ ...defaultOptions, apiBaseUrl: "https://wat.test" })
      })
    ).resolves.toEqual({ error: "save failed: offline or API unreachable.", ok: false });
  });
});
