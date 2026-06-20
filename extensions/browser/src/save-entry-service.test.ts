import { describe, expect, it } from "vitest";

import { handleSaveCustomEntry, saveCustomEntryPayload } from "./save-entry-service.js";
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

describe("save custom entry service", () => {
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
});
