import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { corsHeadersForRequest } from "@/lib/cors";
import { resolveApiIdentity } from "@/lib/api-identity";
import { resolveEntryContemporaries } from "@/lib/contemporaries";

export const runtime = "nodejs";

interface RouteContext {
  params: Promise<{ id: string }>;
}

function json(request: NextRequest, body: unknown, init?: ResponseInit) {
  const headers = new Headers(init?.headers);
  corsHeadersForRequest(request, { methods: "GET, OPTIONS" }).forEach((value, key) =>
    headers.set(key, value)
  );

  return NextResponse.json(body, { ...init, headers });
}

export function OPTIONS(request: NextRequest) {
  return new NextResponse(null, {
    headers: corsHeadersForRequest(request, { methods: "GET, OPTIONS" }),
    status: 204
  });
}

export async function GET(request: NextRequest, context: RouteContext) {
  const identity = resolveApiIdentity(request.headers);
  if (!identity.ok) {
    return apiErrorResponse(request, identity.error, identity.status, {
      headers: corsHeadersForRequest(request, { methods: "GET, OPTIONS" })
    });
  }

  const { id } = await context.params;

  return json(request, await resolveEntryContemporaries(decodeURIComponent(id), identity.identity));
}
