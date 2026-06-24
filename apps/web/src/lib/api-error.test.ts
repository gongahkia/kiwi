import { describe, expect, it } from "vitest";

import { apiErrorBody, apiErrorResponse } from "./api-error";

describe("api errors", () => {
  it("returns the standard error body with request ids", async () => {
    const request = new Request("https://wat.example.com/api/v1/search", {
      headers: { "x-request-id": "req_123" }
    });
    const response = apiErrorResponse(request, "invalid_api_key", 401, {
      message: "supplied API key is invalid"
    });

    expect(response.status).toBe(401);
    expect(response.headers.get("x-request-id")).toBe("req_123");
    await expect(response.json()).resolves.toEqual({
      code: "invalid_api_key",
      error: "invalid_api_key",
      message: "supplied API key is invalid",
      request_id: "req_123"
    });
  });

  it("keeps supplemental fields on rate limit errors", () => {
    const request = new Request("https://wat.example.com/api/v1/search", {
      headers: { "x-request-id": "req_456" }
    });

    expect(apiErrorBody(request, "rate_limited", "rate limited", { remaining: 0 })).toEqual({
      code: "rate_limited",
      error: "rate_limited",
      message: "rate limited",
      remaining: 0,
      request_id: "req_456"
    });
  });
});
