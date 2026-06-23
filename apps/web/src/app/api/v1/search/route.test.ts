import { describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { GET } from "./route";

describe("GET /api/v1/search", () => {
  it("returns contemporaries on every result entry", async () => {
    const response = await GET(new NextRequest("http://localhost/api/v1/search?q=API&limit=1"));
    const body = (await response.json()) as {
      matches: Array<{ entry: { contemporaries?: unknown } }>;
    };

    expect(response.status).toBe(200);
    expect(Array.isArray(body.matches[0]?.entry.contemporaries)).toBe(true);
  });
});
