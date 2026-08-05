import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  JsonFileSlackAutoDetectStore,
  MemorySlackAutoDetectStore
} from "./auto-detect-settings.js";

describe("Slack auto-detect settings", () => {
  it("stores channel opt-ins in memory", async () => {
    const store = new MemorySlackAutoDetectStore();

    await store.setEnabled("T_WAT", "C_DOCS", true);
    expect(await store.isEnabled("T_WAT", "C_DOCS")).toBe(true);
    expect(await store.isEnabled("T_WAT", "C_OTHER")).toBe(false);

    await store.setEnabled("T_WAT", "C_DOCS", false);
    expect(await store.isEnabled("T_WAT", "C_DOCS")).toBe(false);
  });

  it("persists channel opt-ins to JSON", async () => {
    const dir = await mkdtemp(join(tmpdir(), "wat-slack-auto-detect-"));
    const path = join(dir, "settings.json");
    const store = new JsonFileSlackAutoDetectStore(path);

    await store.setEnabled("T_WAT", "C_DOCS", true);
    expect(await new JsonFileSlackAutoDetectStore(path).isEnabled("T_WAT", "C_DOCS")).toBe(true);

    await store.setEnabled("T_WAT", "C_DOCS", false);
    expect(await new JsonFileSlackAutoDetectStore(path).isEnabled("T_WAT", "C_DOCS")).toBe(false);
  });
});
