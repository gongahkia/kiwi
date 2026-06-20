import { NextResponse } from "next/server";

export function GET(request: Request): NextResponse {
  const configuredToken = process.env.ERROR_TEST_TOKEN;
  const suppliedToken = request.headers.get("x-wat-error-test-token");

  if (!configuredToken || suppliedToken !== configuredToken) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  throw new Error("wat error tracking smoke test");
}
