import { NextRequest } from "next/server";
import { describe, expect, it } from "vitest";

import { middleware } from "./middleware";

function nextRequest(method: string, headers: Record<string, string> = {}) {
  return new NextRequest("https://wat.example.com/team/admin/entries/api", {
    headers,
    method
  });
}

describe("middleware csrf guard", () => {
  it("blocks cross-site cookie-authenticated mutations", async () => {
    const response = middleware(
      nextRequest("POST", {
        cookie: "wat_session=dev",
        origin: "https://evil.example"
      })
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({ error: "same_origin_required" });
    expect(response.headers.get("x-request-id")).toBeTruthy();
  });

  it("allows same-origin cookie-authenticated mutations to continue", () => {
    const response = middleware(
      nextRequest("POST", {
        cookie: "wat_session=dev",
        origin: "https://wat.example.com"
      })
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("x-request-id")).toBeTruthy();
  });
});
