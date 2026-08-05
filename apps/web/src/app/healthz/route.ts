import { NextResponse } from "next/server";

import { getHealthSnapshot } from "@/lib/health";

export function GET() {
  return NextResponse.json(getHealthSnapshot());
}
