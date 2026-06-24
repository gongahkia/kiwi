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
    await expect(response.json()).resolves.toMatchObject({
      code: "same_origin_required",
      error: "same_origin_required",
      message: "same origin required"
    });
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

  it("returns REST error bodies instead of redirects for protected APIs", async () => {
    const response = middleware(nextRequest("GET"));

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({
      code: "login_required",
      error: "login_required",
      message: "login required"
    });
  });
});
