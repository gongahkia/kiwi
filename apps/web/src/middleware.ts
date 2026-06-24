import { NextResponse, type NextRequest } from "next/server";
import pino from "pino";

import { hasSameOriginMutationHeaders } from "./lib/csrf";
import { isAdminSession } from "./lib/session";

const sessionCookie = "wat_session";
const protectedPrefixes = ["/team/admin", "/personal"];
const adminPrefix = "/team/admin";
const logger = pino({ name: "wat-web" });

export function middleware(request: NextRequest) {
  const requestId = request.headers.get("x-request-id") ?? crypto.randomUUID();
  const startedAt = Date.now();
  let response: NextResponse;

  const session = request.cookies.get(sessionCookie)?.value;
  const needsSession = protectedPrefixes.some((prefix) =>
    request.nextUrl.pathname.startsWith(prefix)
  );
  const needsAdmin = request.nextUrl.pathname.startsWith(adminPrefix);

  if (session && !hasSameOriginMutationHeaders(request)) {
    response = NextResponse.json({ error: "same_origin_required" }, { status: 403 });
  } else if (needsSession && !session) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("next", `${request.nextUrl.pathname}${request.nextUrl.search}`);
    response = NextResponse.redirect(loginUrl);
  } else if (needsAdmin && session && !isAdminSession(session)) {
    response = new NextResponse("Forbidden", { status: 403 });
  } else {
    response = NextResponse.next();
  }

  response.headers.set("x-request-id", requestId);
  logger.info({
    duration_ms: Date.now() - startedAt,
    event: "request",
    method: request.method,
    path: request.nextUrl.pathname,
    request_id: requestId,
    status: response.status
  });

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|robots.txt|sitemap.xml).*)"],
  runtime: "nodejs"
};
