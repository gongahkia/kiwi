import { describe, expect, it } from "vitest";

import { corsHeadersForRequest } from "./cors";

function request(origin: string | null): Request {
  return new Request("http://localhost/api/v1/search", {
    headers: origin ? { origin } : undefined
  });
}

describe("corsHeadersForRequest", () => {
  it("echoes configured web origins", () => {
    const headers = corsHeadersForRequest(request("https://wat.example.com"), {
      env: { WAT_ALLOWED_ORIGINS: "https://wat.example.com" },
      methods: "GET, OPTIONS"
    });

    expect(headers.get("access-control-allow-origin")).toBe("https://wat.example.com");
    expect(headers.get("access-control-allow-credentials")).toBe("true");
    expect(headers.get("vary")).toBe("Origin");
  });

  it("echoes configured extension origins", () => {
    const headers = corsHeadersForRequest(request("chrome-extension://abc123"), {
      env: { WAT_EXTENSION_ORIGINS: "chrome-extension://abc123" },
      methods: "GET, OPTIONS"
    });

    expect(headers.get("access-control-allow-origin")).toBe("chrome-extension://abc123");
  });

  it("does not allow unconfigured origins", () => {
    const headers = corsHeadersForRequest(request("https://evil.example"), {
      env: { WAT_ALLOWED_ORIGINS: "https://wat.example.com" },
      methods: "GET, OPTIONS"
    });

    expect(headers.get("access-control-allow-origin")).toBeNull();
  });
});
