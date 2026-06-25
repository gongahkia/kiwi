import type { NextRequest } from "next/server";

import { deleteDiscordInstallation, postDiscordInstallation } from "./handler";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  return postDiscordInstallation(request);
}

export async function DELETE(request: NextRequest) {
  return deleteDiscordInstallation(request);
}
