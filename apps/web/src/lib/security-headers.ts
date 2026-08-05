export interface ResponseHeader {
  key: string;
  value: string;
}

export interface HeaderRule {
  source: string;
  headers: ResponseHeader[];
}

export const publicEntryCacheControl =
  "public, max-age=300, s-maxage=86400, stale-while-revalidate=604800";

export function contentSecurityPolicyForEnvironment(environment = process.env.NODE_ENV): string {
  return [
    "default-src 'self'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "object-src 'none'",
    "img-src 'self' data: blob:",
    "font-src 'self' data:",
    environment === "production"
      ? "script-src 'self' 'unsafe-inline'"
      : "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
    "style-src 'self' 'unsafe-inline'",
    "connect-src 'self'",
    ...(environment === "production" ? ["upgrade-insecure-requests"] : [])
  ].join("; ");
}

export function securityHeadersForEnvironment(
  environment = process.env.NODE_ENV
): ResponseHeader[] {
  const headers: ResponseHeader[] = [
    {
      key: "Content-Security-Policy",
      value: contentSecurityPolicyForEnvironment(environment)
    },
    {
      key: "X-Frame-Options",
      value: "DENY"
    },
    {
      key: "X-Content-Type-Options",
      value: "nosniff"
    },
    {
      key: "Referrer-Policy",
      value: "strict-origin-when-cross-origin"
    },
    {
      key: "Permissions-Policy",
      value: "camera=(), microphone=(), geolocation=()"
    }
  ];

  if (environment === "production") {
    headers.push({
      key: "Strict-Transport-Security",
      value: "max-age=31536000; includeSubDomains"
    });
  }

  return headers;
}

export function securityHeaderRules(environment = process.env.NODE_ENV): HeaderRule[] {
  return [
    {
      source: "/:path*",
      headers: securityHeadersForEnvironment(environment)
    }
  ];
}

export function cacheHeaderRules(): HeaderRule[] {
  return [
    {
      source: "/term/:path*",
      headers: [{ key: "Cache-Control", value: publicEntryCacheControl }]
    }
  ];
}

export function nextHeaderRules(environment = process.env.NODE_ENV): HeaderRule[] {
  return [...securityHeaderRules(environment), ...cacheHeaderRules()];
}
