import { NextResponse } from "next/server";

import { getEmailOutbox } from "@/lib/email-notifications";

export function GET() {
  return NextResponse.json({ notifications: getEmailOutbox() });
}
