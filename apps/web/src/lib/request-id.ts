export const requestIdHeader = "x-request-id";

type HeaderReader = {
  get(name: string): string | null;
};

export function requestIdFromHeaders(headers: HeaderReader | undefined): string | undefined {
  return headers?.get(requestIdHeader)?.trim() || undefined;
}

export function ensureRequestId(headers: HeaderReader | undefined): string {
  return requestIdFromHeaders(headers) ?? crypto.randomUUID();
}
