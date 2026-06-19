import { NextResponse, type NextRequest } from "next/server";

const sessionCookie = "wat_session";

export function middleware(request: NextRequest) {
  if (request.cookies.has(sessionCookie)) {
    return NextResponse.next();
  }

  const loginUrl = new URL("/login", request.url);
  loginUrl.searchParams.set("next", request.nextUrl.pathname);
  return NextResponse.redirect(loginUrl);
}

export const config = {
  matcher: ["/team/admin/:path*"]
};
