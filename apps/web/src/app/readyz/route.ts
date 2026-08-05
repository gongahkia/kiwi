import { NextResponse } from "next/server";

import { getReadinessSnapshot } from "@/lib/health";

export async function GET() {
  const snapshot = await getReadinessSnapshot();
  return NextResponse.json(snapshot, { status: snapshot.status === "ok" ? 200 : 503 });
}
