export class ExtensionApiError extends Error {
  readonly status?: number;

  constructor(message: string, status?: number) {
    super(message);
    this.name = "ExtensionApiError";
    this.status = status;
  }
}

type ErrorBody = {
  error?: unknown;
  retry_after?: unknown;
};

async function errorBody(response: Pick<Response, "json">): Promise<ErrorBody> {
  try {
    return (await response.json()) as ErrorBody;
  } catch {
    return {};
  }
}

function detailText(body: ErrorBody): string {
  return typeof body.error === "string" && body.error.trim() ? `: ${body.error.trim()}` : "";
}

function retryText(response: Pick<Response, "headers">, body: ErrorBody): string {
  const retryAfter = response.headers.get("retry-after") ?? body.retry_after;
  if (typeof retryAfter === "number" && Number.isFinite(retryAfter)) {
    return ` Retry after ${retryAfter}s.`;
  }
  if (typeof retryAfter === "string" && retryAfter.trim()) {
    const trimmed = retryAfter.trim();
    return Number.isFinite(Number(trimmed))
      ? ` Retry after ${trimmed}s.`
      : ` Retry after ${trimmed}.`;
  }

  return "";
}

export async function apiErrorFromResponse(
  action: "lookup" | "save",
  response: Pick<Response, "headers" | "json" | "status">
): Promise<ExtensionApiError> {
  const body = await errorBody(response);
  const prefix = `${action} failed`;

  switch (response.status) {
    case 400:
      return new ExtensionApiError(`${prefix}: validation error${detailText(body)}`, 400);
    case 401:
      return new ExtensionApiError(`${prefix}: unauthorized. Check API token.`, 401);
    case 403:
      return new ExtensionApiError(`${prefix}: forbidden. Check account or team access.`, 403);
    case 429:
      return new ExtensionApiError(`${prefix}: rate-limited.${retryText(response, body)}`, 429);
    default:
      return new ExtensionApiError(
        `${prefix}: HTTP ${response.status}${detailText(body)}`,
        response.status
      );
  }
}

export function offlineApiError(action: "lookup" | "save"): ExtensionApiError {
  return new ExtensionApiError(`${action} failed: offline or API unreachable.`);
}

export function apiErrorResult(
  error: unknown,
  fallback: string
): { error: string; ok: false; status?: number } {
  if (error instanceof ExtensionApiError) {
    return {
      error: error.message,
      ok: false,
      ...(error.status == null ? {} : { status: error.status })
    };
  }

  return { error: error instanceof Error ? error.message : fallback, ok: false };
}
