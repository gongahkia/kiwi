import type { NextResponse } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";

export function GET(request: Request): NextResponse {
  const configuredToken = process.env.ERROR_TEST_TOKEN;
  const suppliedToken = request.headers.get("x-wat-error-test-token");

  if (!configuredToken || suppliedToken !== configuredToken) {
    return apiErrorResponse(request, "not_found", 404);
  }

  throw new Error("wat error tracking smoke test");
}
