import type { NextRequest } from "next/server";

import { getTeamsSearch } from "./handler";

export const runtime = "nodejs";

export async function GET(request: NextRequest) {
  return getTeamsSearch(request);
}
