import { describe, expect, it } from "vitest";
import { NextRequest } from "next/server";

import { GET } from "./route";

describe("GET /api/v1/entries/:id/contemporaries", () => {
  it("returns 200 with resolved entries", async () => {
    const response = await GET(
      new NextRequest(
        "http://localhost/api/v1/entries/seed-csr-client-side-rendering/contemporaries"
      ),
      { params: Promise.resolve({ id: "seed-csr-client-side-rendering" }) }
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual([
      {
        id: "seed-ssr-server-side-rendering",
        meaning_short: "Rendering UI markup on the server before sending it to the client.",
        term: "SSR"
      }
    ]);
  });
});
