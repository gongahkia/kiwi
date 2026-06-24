import { NextResponse, type NextRequest } from "next/server";
import pino from "pino";

import { apiErrorResponse } from "./lib/api-error";
import { hasSameOriginMutationHeaders } from "./lib/csrf";
import { ensureRequestId, requestIdHeader } from "./lib/request-id";
import { safeLogFields } from "./lib/safe-logging";
import { isAdminSession } from "./lib/session";

const sessionCookie = "wat_session";
const protectedPrefixes = ["/team/admin", "/personal"];
const adminPrefix = "/team/admin";
const logger = pino({ name: "wat-web" });

function isRestEndpoint(pathname: string): boolean {
  return (
    pathname.startsWith("/api/") ||
    pathname.endsWith("/api") ||
    pathname.includes("/api/") ||
    pathname.includes("/export/") ||
    pathname.endsWith("/import")
  );
}

export function middleware(request: NextRequest) {
  const requestId = ensureRequestId(request.headers);
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(requestIdHeader, requestId);
  const startedAt = Date.now();
  let response: NextResponse;

  const session = request.cookies.get(sessionCookie)?.value;
  const needsSession = protectedPrefixes.some((prefix) =>
    request.nextUrl.pathname.startsWith(prefix)
  );
  const needsAdmin = request.nextUrl.pathname.startsWith(adminPrefix);

  if (session && !hasSameOriginMutationHeaders(request)) {
    response = apiErrorResponse(request, "same_origin_required", 403, {
      message: "same origin required",
      requestId
    });
  } else if (needsSession && !session) {
    if (isRestEndpoint(request.nextUrl.pathname)) {
      response = apiErrorResponse(request, "login_required", 401, {
        message: "login required",
        requestId
      });
    } else {
      const loginUrl = new URL("/login", request.url);
      loginUrl.searchParams.set("next", `${request.nextUrl.pathname}${request.nextUrl.search}`);
      response = NextResponse.redirect(loginUrl);
    }
  } else if (needsAdmin && session && !isAdminSession(session)) {
    response = isRestEndpoint(request.nextUrl.pathname)
      ? apiErrorResponse(request, "admin_required", 403, {
          message: "admin required",
          requestId
        })
      : new NextResponse("Forbidden", { status: 403 });
  } else {
    response = NextResponse.next({
      request: {
        headers: requestHeaders
      }
    });
  }

  response.headers.set(requestIdHeader, requestId);
  logger.info(
    safeLogFields({
      duration_ms: Date.now() - startedAt,
      event: "request",
      method: request.method,
      path: request.nextUrl.pathname,
      request_id: requestId,
      status: response.status
    })
  );

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|robots.txt|sitemap.xml).*)"],
  runtime: "nodejs"
};
