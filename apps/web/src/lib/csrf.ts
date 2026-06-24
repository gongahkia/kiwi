type HeaderReader = {
  get(name: string): string | null;
};

export type SameOriginRequest = {
  headers: HeaderReader;
  method: string;
  url: string;
};

const safeMethods = new Set(["GET", "HEAD", "OPTIONS"]);

export function isUnsafeMethod(method: string): boolean {
  return !safeMethods.has(method.toUpperCase());
}

function originFor(value: string): string | null {
  try {
    return new URL(value).origin;
  } catch {
    return null;
  }
}

export function hasSameOriginMutationHeaders(request: SameOriginRequest): boolean {
  if (!isUnsafeMethod(request.method)) return true;

  const expectedOrigin = originFor(request.url);
  if (!expectedOrigin) return false;

  const origin = request.headers.get("origin");
  if (origin) return originFor(origin) === expectedOrigin;

  const referer = request.headers.get("referer");
  if (referer) return originFor(referer) === expectedOrigin;

  return false;
}
