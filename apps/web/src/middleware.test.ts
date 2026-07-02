import { NextRequest } from "next/server";
import { describe, expect, it } from "vitest";

import { middleware } from "./middleware";
import { testSessionToken } from "./lib/session";

function nextRequest(
  method: string,
  headers: Record<string, string> = {},
  path = "/team/admin/entries/api"
) {
  return new NextRequest(`https://wat.example.com${path}`, {
    headers,
    method
  });
}

describe("middleware csrf guard", () => {
  it("blocks cross-site cookie-authenticated mutations", async () => {
    const response = await middleware(
      nextRequest("POST", {
        cookie: `next-auth.session-token=${testSessionToken()}`,
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

  it("allows same-origin cookie-authenticated mutations to continue", async () => {
    const response = await middleware(
      nextRequest("POST", {
        cookie: `next-auth.session-token=${testSessionToken()}`,
        origin: "https://wat.example.com"
      })
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("x-request-id")).toBeTruthy();
  });

  it("returns REST error bodies instead of redirects for protected APIs", async () => {
    const response = await middleware(nextRequest("GET"));

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({
      code: "login_required",
      error: "login_required",
      message: "login required"
    });
  });

  it("lets API-key team imports reach route auth", async () => {
    const response = await middleware(
      nextRequest("POST", { authorization: "Bearer import-key" }, "/team/admin/import/api")
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("x-request-id")).toBeTruthy();
  });
});
