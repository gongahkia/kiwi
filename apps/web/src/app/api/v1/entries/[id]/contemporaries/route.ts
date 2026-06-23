import { NextResponse, type NextRequest } from "next/server";

import { resolveApiIdentity } from "@/lib/api-identity";
import { resolveEntryContemporaries } from "@/lib/contemporaries";

export const runtime = "nodejs";

interface RouteContext {
  params: Promise<{ id: string }> | { id: string };
}

function corsHeaders() {
  return {
    "access-control-allow-headers":
      "authorization, content-type, x-api-key, x-wat-team-id, x-wat-user-id",
    "access-control-allow-methods": "GET, OPTIONS",
    "access-control-allow-origin": "*"
  };
}

function json(body: unknown, init?: ResponseInit) {
  const headers = new Headers(init?.headers);
  for (const [key, value] of Object.entries(corsHeaders())) {
    headers.set(key, value);
  }

  return NextResponse.json(body, { ...init, headers });
}

export function OPTIONS() {
  return new NextResponse(null, { headers: corsHeaders(), status: 204 });
}

export async function GET(request: NextRequest, context: RouteContext) {
  const identity = resolveApiIdentity(request.headers);
  if (!identity.ok) {
    return json({ error: identity.error }, { status: identity.status });
  }

  const { id } = await context.params;

  return json(await resolveEntryContemporaries(decodeURIComponent(id), identity.identity));
}
