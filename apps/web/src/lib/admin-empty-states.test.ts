import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { adminEmptyStates } from "./admin-empty-states";

describe("admin empty states", () => {
  it("covers team entries, suggestions, members, and api keys", () => {
    expect(Object.keys(adminEmptyStates).sort()).toEqual([
      "apiKeys",
      "members",
      "suggestions",
      "teamEntries"
    ]);

    for (const state of Object.values(adminEmptyStates)) {
      expect(state.title).toMatch(/\S/);
      expect(state.body).toMatch(/\S/);
      expect(state.actionHref).toMatch(/^\//);
      expect(state.actionLabel).toMatch(/\S/);
    }
  });

  it("wires each required empty state into an admin page", () => {
    const sources = [
      "src/components/team-entry-crud.tsx",
      "src/components/suggestion-review-queue.tsx",
      "src/app/team/admin/members/page.tsx",
      "src/app/team/admin/api-keys/page.tsx"
    ]
      .map((path) => readFileSync(join(process.cwd(), path), "utf8"))
      .join("\n");

    expect(sources).toContain("adminEmptyStates.teamEntries");
    expect(sources).toContain("adminEmptyStates.suggestions");
    expect(sources).toContain("adminEmptyStates.members");
    expect(sources).toContain("adminEmptyStates.apiKeys");
  });
});
