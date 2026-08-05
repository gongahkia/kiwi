const redacted = "[redacted]";

const secretKeyPattern =
  /api[-_]?key|authorization|cookie|oauth|password|secret|session|token|magic[-_]?link/i;
const privatePayloadKeyPattern =
  /^(body|definition|expansion|meaning|message|q|query|raw_query|snippet|stack)$/i;
const pathKeyPattern = /^(path|route|url)$/i;

const sensitiveTextPatterns: Array<[RegExp, string]> = [
  [/\b(authorization=)Bearer\s+[A-Za-z0-9._~+/=-]+/gi, "$1[redacted]"],
  [/\bBearer\s+[A-Za-z0-9._~+/=-]+/gi, "Bearer [redacted]"],
  [/\bxox[a-z]-[A-Za-z0-9-]+/gi, redacted],
  [/\bwat[_-]?api[_-]?key[_-]?[A-Za-z0-9_=-]{8,}\b/gi, redacted],
  [
    /\b(api[-_]?key|authorization|cookie|magic[-_]?link|oauth|password|q|query|secret|token)=([^&\s",}]+)/gi,
    "$1=[redacted]"
  ],
  [/[?&](q|query|api[-_]?key|token|magic[-_]?link)=([^&\s]+)/gi, "?$1=[redacted]"]
];

export function redactLogText(value: string): string {
  return sensitiveTextPatterns.reduce(
    (current, [pattern, replacement]) => current.replace(pattern, replacement),
    value
  );
}

function safeLogValue(value: unknown, key?: string): unknown {
  if (key && (secretKeyPattern.test(key) || privatePayloadKeyPattern.test(key))) {
    return redacted;
  }

  if (typeof value === "string") {
    const pathSafeValue = key && pathKeyPattern.test(key) ? (value.split("?")[0] ?? "") : value;
    return redactLogText(pathSafeValue);
  }

  if (Array.isArray(value)) {
    return value.map((item) => safeLogValue(item));
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([entryKey, entryValue]) => [
        entryKey,
        safeLogValue(entryValue, entryKey)
      ])
    );
  }

  return value;
}

export function safeLogFields<T>(fields: T): T {
  return safeLogValue(fields) as T;
}
