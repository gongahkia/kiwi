import { afterEach, describe, expect, it, vi } from "vitest";
import type { SearchEntry } from "@wat/search";

import { copyTextToClipboard, formatCitation } from "./copy-citation";

const entry: SearchEntry = {
  aliases: [],
  confidence_tier: "T1",
  contemporaries: [],
  domains: ["web"],
  expansions: ["Application Programming Interface"],
  id: "api",
  layer: "public",
  meaning_short: "A contract for software calls.",
  sources: [
    {
      license: "CC-BY-4.0",
      publisher: "MDN",
      retrieved_at: "2026-06-20T00:00:00.000Z",
      snippet: "API reference.",
      source_quality: "canonical",
      title: "API",
      url: "https://developer.mozilla.org/docs/Glossary/API"
    }
  ],
  term: "API",
  term_normalized: "api"
};

describe("copy citation button helpers", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("formats sourced markdown citation", () => {
    expect(formatCitation(entry)).toBe(
      "**API** — Application Programming Interface. [API](https://developer.mozilla.org/docs/Glossary/API) (MDN, CC-BY-4.0)."
    );
  });

  it("uses navigator clipboard when available", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal("navigator", { clipboard: { writeText } });

    await expect(copyTextToClipboard("citation")).resolves.toBe(true);
    expect(writeText).toHaveBeenCalledWith("citation");
  });

  it("falls back when navigator clipboard is unavailable", async () => {
    const textarea = {
      dataset: {} as Record<string, string>,
      focus: vi.fn(),
      remove: vi.fn(),
      select: vi.fn(),
      setAttribute: vi.fn(),
      setSelectionRange: vi.fn(),
      style: {} as Record<string, string>,
      value: ""
    };
    const appendChild = vi.fn();
    const execCommand = vi.fn().mockReturnValue(true);
    vi.stubGlobal("navigator", {});
    vi.stubGlobal("document", {
      activeElement: { focus: vi.fn() },
      body: { appendChild },
      createElement: vi.fn().mockReturnValue(textarea),
      execCommand,
      getSelection: vi.fn().mockReturnValue({
        addRange: vi.fn(),
        getRangeAt: vi.fn(),
        rangeCount: 0,
        removeAllRanges: vi.fn()
      })
    });

    await expect(copyTextToClipboard("citation")).resolves.toBe(true);
    expect(appendChild).toHaveBeenCalledWith(textarea);
    expect(textarea.focus).toHaveBeenCalled();
    expect(textarea.setSelectionRange).toHaveBeenCalledWith(0, "citation".length);
    expect(execCommand).toHaveBeenCalledWith("copy");
    expect(textarea.remove).toHaveBeenCalled();
  });

  it("falls back when navigator clipboard rejects", async () => {
    const writeText = vi.fn().mockRejectedValue(new Error("denied"));
    const textarea = {
      dataset: {} as Record<string, string>,
      focus: vi.fn(),
      remove: vi.fn(),
      select: vi.fn(),
      setAttribute: vi.fn(),
      setSelectionRange: vi.fn(),
      style: {} as Record<string, string>,
      value: ""
    };
    const execCommand = vi.fn().mockReturnValue(true);
    vi.stubGlobal("navigator", { clipboard: { writeText } });
    vi.stubGlobal("document", {
      activeElement: { focus: vi.fn() },
      body: { appendChild: vi.fn() },
      createElement: vi.fn().mockReturnValue(textarea),
      execCommand
    });

    await expect(copyTextToClipboard("citation")).resolves.toBe(true);
    expect(writeText).toHaveBeenCalledWith("citation");
    expect(execCommand).toHaveBeenCalledWith("copy");
  });

  it("returns false when no clipboard path is available", async () => {
    vi.stubGlobal("navigator", {});
    vi.stubGlobal("document", {});

    await expect(copyTextToClipboard("citation")).resolves.toBe(false);
  });
});
