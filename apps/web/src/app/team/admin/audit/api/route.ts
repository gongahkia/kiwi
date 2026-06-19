import { NextResponse } from "next/server";

import { getAuditLog } from "@/lib/audit-log";

export function GET() {
  return NextResponse.json({ audit: getAuditLog() });
}
