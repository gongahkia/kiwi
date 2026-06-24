import { NextResponse } from "next/server";

import { ensureRequestId, requestIdHeader } from "./request-id";

interface ApiErrorOptions {
  fields?: Record<string, unknown>;
  headers?: HeadersInit;
  message?: string;
  requestId?: string;
}

export interface ApiErrorBody {
  code: string;
  error: string;
  message: string;
  request_id: string;
  [key: string]: unknown;
}

export function apiErrorBody(
  request: Request,
  code: string,
  message = code,
  fields: Record<string, unknown> = {}
): ApiErrorBody {
  const { request_id: ignoredRequestId, ...safeFields } = fields;
  const requestId =
    typeof ignoredRequestId === "string" ? ignoredRequestId : ensureRequestId(request.headers);

  return {
    ...safeFields,
    error: code,
    code,
    message,
    request_id: requestId
  };
}

export function apiErrorResponse(
  request: Request,
  code: string,
  status: number,
  options: ApiErrorOptions = {}
): NextResponse {
  const headers = new Headers(options.headers);
  const requestId = options.requestId ?? ensureRequestId(request.headers);
  headers.set(requestIdHeader, requestId);

  return NextResponse.json(
    {
      ...options.fields,
      error: code,
      code,
      message: options.message ?? code,
      request_id: requestId
    },
    { headers, status }
  );
}
