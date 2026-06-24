import { safeLogFields } from "./safe-logging";

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
  const safeMetadata = safeLogFields(metadata);
  const safeError = safeLogFields(normalized);

  return {
    ...safeMetadata,
    message: safeError.message,
    name: safeError.name,
    runtime: "server",
    stack: safeError.stack,
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
    console.error(
      "wat error tracking delivery failed",
      safeLogFields(normalizeError(reportingError))
    );
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
