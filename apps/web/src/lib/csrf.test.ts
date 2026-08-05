import { describe, expect, it } from "vitest";

import { hasSameOriginMutationHeaders, isUnsafeMethod } from "./csrf";

function request(method: string, headers: Record<string, string> = {}) {
  return {
    headers: new Headers(headers),
    method,
    url: "https://wat.example.com/team/admin/entries/api"
  };
}

describe("csrf same-origin checks", () => {
  it("treats safe methods as allowed", () => {
    expect(isUnsafeMethod("GET")).toBe(false);
    expect(hasSameOriginMutationHeaders(request("GET"))).toBe(true);
    expect(hasSameOriginMutationHeaders(request("OPTIONS"))).toBe(true);
  });

  it("accepts same-origin mutation origin headers", () => {
    expect(
      hasSameOriginMutationHeaders(request("POST", { origin: "https://wat.example.com" }))
    ).toBe(true);
  });

  it("accepts same-origin mutation referer headers", () => {
    expect(
      hasSameOriginMutationHeaders(
        request("PATCH", { referer: "https://wat.example.com/team/admin" })
      )
    ).toBe(true);
  });

  it("accepts browser fetch metadata for same-origin mutations", () => {
    expect(hasSameOriginMutationHeaders(request("POST", { "sec-fetch-site": "same-origin" }))).toBe(
      true
    );
    expect(hasSameOriginMutationHeaders(request("POST", { "sec-fetch-site": "none" }))).toBe(true);
    expect(
      hasSameOriginMutationHeaders(
        request("POST", {
          origin: "https://localhost:3000",
          "sec-fetch-site": "same-origin"
        })
      )
    ).toBe(true);
  });

  it("accepts same-origin custom headers for JavaScript mutations", () => {
    expect(hasSameOriginMutationHeaders(request("POST", { "x-wat-same-origin": "1" }))).toBe(true);
  });

  it("rejects cross-site mutation headers", () => {
    expect(
      hasSameOriginMutationHeaders(request("DELETE", { origin: "https://evil.example" }))
    ).toBe(false);
    expect(
      hasSameOriginMutationHeaders(request("POST", { referer: "https://evil.example/form" }))
    ).toBe(false);
    expect(hasSameOriginMutationHeaders(request("POST", { "sec-fetch-site": "cross-site" }))).toBe(
      false
    );
    expect(hasSameOriginMutationHeaders(request("POST", { "x-wat-same-origin": "0" }))).toBe(false);
  });

  it("rejects mutation requests without same-origin evidence", () => {
    expect(hasSameOriginMutationHeaders(request("POST"))).toBe(false);
    expect(hasSameOriginMutationHeaders(request("POST", { origin: "not a url" }))).toBe(false);
  });
});
