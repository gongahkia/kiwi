import { NextResponse, type NextRequest } from "next/server";
import pino from "pino";

const sessionCookie = "wat_session";
const logger = pino({ name: "wat-web" });

export function middleware(request: NextRequest) {
  const requestId = request.headers.get("x-request-id") ?? crypto.randomUUID();
  const startedAt = Date.now();
  let response: NextResponse;

  if (request.nextUrl.pathname.startsWith("/team/admin") && !request.cookies.has(sessionCookie)) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("next", request.nextUrl.pathname);
    response = NextResponse.redirect(loginUrl);
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
