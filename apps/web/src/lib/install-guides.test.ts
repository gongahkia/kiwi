import { describe, expect, it } from "vitest";

import { installGuideById, installGuides } from "./install-guides";

describe("install guides", () => {
  it("covers required surfaces with role, environment, and steps", () => {
    expect(installGuides.map((guide) => guide.id)).toEqual([
      "slack",
      "teams",
      "discord",
      "web",
      "extension",
      "mcp",
      "api",
      "self-host"
    ]);

    for (const guide of installGuides) {
      expect(guide.role).not.toHaveLength(0);
      expect(guide.environment).not.toHaveLength(0);
      expect(guide.steps.length).toBeGreaterThan(0);
    }
  });

  it("looks up guides by route id", () => {
    expect(installGuideById("api")?.href).toBe("/install/api");
    expect(installGuideById("unknown")).toBeNull();
  });
});
