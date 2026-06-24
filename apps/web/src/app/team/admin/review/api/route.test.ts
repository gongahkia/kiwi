import { NextRequest } from "next/server";
import { afterEach, describe, expect, it } from "vitest";

import { resetSuggestedEditsForTest, submitNewEntrySuggestion } from "@/lib/suggestions";
import { GET } from "./route";

const suggestionInput = {
  domains: ["ops"],
  expansion: "Change Approval Process",
  meaning: "Internal release approval shorthand.",
  source_url: "https://docs.example.com/cap",
  term: "CAP"
};

describe("GET /team/admin/review/api", () => {
  afterEach(resetSuggestedEditsForTest);

  it("paginates review suggestions", async () => {
    submitNewEntrySuggestion("user_1", suggestionInput);
    submitNewEntrySuggestion("user_2", { ...suggestionInput, term: "RTO" });

    const response = GET(new NextRequest("https://wat.example.com/team/admin/review/api?limit=1"));
    const body = (await response.json()) as {
      page: { limit: number; next_cursor: string | null; total: number };
      suggestions: unknown[];
    };

    expect(body.suggestions).toHaveLength(1);
    expect(body.page).toMatchObject({ limit: 1, next_cursor: "1", total: 2 });
  });
});
