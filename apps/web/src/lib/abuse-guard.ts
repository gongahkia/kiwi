const suspiciousPatterns = [
  /<\s*script\b/iu,
  /\bunion\s+select\b/iu,
  /\bor\s+['"]?\d+['"]?\s*=\s*['"]?\d+['"]?/iu,
  /\bselect\b.+\bfrom\b/iu,
  /\.\.\//u,
  /%00/iu,
  /\$\{jndi:/iu
];

export interface AbuseDecision {
  allowed: boolean;
  reason?: "overlong_url" | "suspicious_probe";
}

export function checkAbusiveRequest(url: URL): AbuseDecision {
  const raw = `${url.pathname}${url.search}`;
  const decoded = decodeUrl(raw);
  const value = `${raw}\n${decoded}`;
  if (value.length > 4096) return { allowed: false, reason: "overlong_url" };
  return suspiciousPatterns.some((pattern) => pattern.test(value))
    ? { allowed: false, reason: "suspicious_probe" }
    : { allowed: true };
}

function decodeUrl(value: string): string {
  try {
    return decodeURIComponent(value.replace(/\+/gu, " "));
  } catch {
    return value;
  }
}
