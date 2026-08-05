import type { NextRequest } from "next/server";

import { deleteTeamsInstallation, postTeamsInstallation } from "./handler";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  return postTeamsInstallation(request);
}

export async function DELETE(request: NextRequest) {
  return deleteTeamsInstallation(request);
}
