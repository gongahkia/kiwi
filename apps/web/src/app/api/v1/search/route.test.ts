import { afterEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

import { GET, OPTIONS } from "./route";

const previousAllowedOrigins = process.env.WAT_ALLOWED_ORIGINS;

describe("GET /api/v1/search", () => {
  afterEach(() => {
    if (previousAllowedOrigins === undefined) {
      delete process.env.WAT_ALLOWED_ORIGINS;
    } else {
      process.env.WAT_ALLOWED_ORIGINS = previousAllowedOrigins;
    }
  });

  it("returns contemporaries on every result entry", async () => {
    const response = await GET(new NextRequest("http://localhost/api/v1/search?q=API&limit=1"));
    const body = (await response.json()) as {
      matches: Array<{ entry: { contemporaries?: unknown } }>;
    };

    expect(response.status).toBe(200);
    expect(Array.isArray(body.matches[0]?.entry.contemporaries)).toBe(true);
  });

  it("logs and returns request ids", async () => {
    const log = vi.spyOn(console, "info").mockImplementation(() => undefined);

    const response = await GET(
      new NextRequest("http://localhost/api/v1/search?q=API&limit=1", {
        headers: { "x-request-id": "req_123" }
      })
    );

    expect(response.headers.get("x-request-id")).toBe("req_123");
    const event = JSON.parse(String(log.mock.calls[0]?.[0])) as { request_id?: string };
    expect(event.request_id).toBe("req_123");
    log.mockRestore();
  });

  it("uses configured CORS origins", () => {
    process.env.WAT_ALLOWED_ORIGINS = "https://wat.example.com";
    const response = OPTIONS(
      new NextRequest("http://localhost/api/v1/search", {
        headers: { origin: "https://wat.example.com" }
      })
    );

    expect(response.headers.get("access-control-allow-origin")).toBe("https://wat.example.com");
    expect(response.headers.get("access-control-allow-credentials")).toBe("true");
  });
});
