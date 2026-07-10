import { describe, expect, it } from "vitest";

import {
  cacheHeaderRules,
  contentSecurityPolicyForEnvironment,
  nextHeaderRules,
  publicEntryCacheControl,
  securityHeaderRules,
  securityHeadersForEnvironment
} from "./security-headers";

describe("security headers", () => {
  it("sets required production security headers", () => {
    const headers = headerMap(securityHeadersForEnvironment("production"));

    expect(headers.get("Content-Security-Policy")).toBe(
      contentSecurityPolicyForEnvironment("production")
    );
    expect(headers.get("Content-Security-Policy")).toContain("frame-ancestors 'none'");
    expect(headers.get("Content-Security-Policy")).toContain("upgrade-insecure-requests");
    expect(headers.get("Content-Security-Policy")).not.toContain("'unsafe-eval'");
    expect(headers.get("Strict-Transport-Security")).toBe("max-age=31536000; includeSubDomains");
    expect(headers.get("X-Frame-Options")).toBe("DENY");
    expect(headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(headers.get("Referrer-Policy")).toBe("strict-origin-when-cross-origin");
  });

  it("omits HSTS outside production", () => {
    const headers = headerMap(securityHeadersForEnvironment("development"));

    expect(headers.has("Strict-Transport-Security")).toBe(false);
    expect(headers.get("Content-Security-Policy")).toBe(
      contentSecurityPolicyForEnvironment("development")
    );
    expect(headers.get("Content-Security-Policy")).not.toContain("upgrade-insecure-requests");
  });

  it("applies headers to every Next route", () => {
    expect(securityHeaderRules("production")).toEqual([
      {
        source: "/:path*",
        headers: securityHeadersForEnvironment("production")
      }
    ]);
  });

  it("adds CDN cache headers to public term pages", () => {
    expect(cacheHeaderRules()).toEqual([
      {
        source: "/term/:path*",
        headers: [{ key: "Cache-Control", value: publicEntryCacheControl }]
      }
    ]);
    expect(publicEntryCacheControl).toContain("s-maxage=86400");
    expect(nextHeaderRules("production")).toEqual([
      ...securityHeaderRules("production"),
      ...cacheHeaderRules()
    ]);
  });
});

function headerMap(headers: { key: string; value: string }[]): Map<string, string> {
  return new Map(headers.map((header) => [header.key, header.value]));
}
