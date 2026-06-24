export type ErrorReportMetadata = {
  method?: string;
  request_id?: string;
  route?: string;
  source?: string;
};

export type ErrorReport = ErrorReportMetadata & {
  message: string;
  name: string;
  runtime: "server";
  stack?: string;
  timestamp: string;
};

type FetchLike = typeof fetch;

export function buildErrorReport(
  error: unknown,
  metadata: ErrorReportMetadata = {},
  now: Date = new Date()
): ErrorReport {
  const normalized = normalizeError(error);

  return {
    ...metadata,
    message: normalized.message,
    name: normalized.name,
    runtime: "server",
    stack: normalized.stack,
    timestamp: now.toISOString()
  };
}

export async function reportError(
  error: unknown,
  metadata: ErrorReportMetadata = {},
  env: Record<string, string | undefined> = process.env,
  fetchImpl: FetchLike = fetch
): Promise<{ delivered: boolean; status?: number }> {
  const report = buildErrorReport(error, metadata);
  const webhookUrl = env.ERROR_TRACKING_WEBHOOK_URL;

  console.error("wat server error", report);

  if (!webhookUrl) {
    return { delivered: false };
  }

  try {
    const response = await fetchImpl(webhookUrl, {
      body: JSON.stringify(report),
      headers: { "content-type": "application/json" },
      method: "POST"
    });

    return { delivered: response.ok, status: response.status };
  } catch (reportingError) {
    console.error("wat error tracking delivery failed", normalizeError(reportingError));
    return { delivered: false };
  }
}

function normalizeError(error: unknown): { message: string; name: string; stack?: string } {
  if (error instanceof Error) {
    return {
      message: error.message,
      name: error.name,
      stack: error.stack
    };
  }

  return {
    message: typeof error === "string" ? error : JSON.stringify(error),
    name: "NonError"
  };
}
