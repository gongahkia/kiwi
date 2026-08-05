import type { NextRequest } from "next/server";

import { postApiSuggestion } from "./handler";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  return postApiSuggestion(request);
}
