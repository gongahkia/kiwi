import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import {
  createPersonalEntry,
  deletePersonalEntry,
  getPersonalEntries,
  updatePersonalEntry,
  type PersonalEntry
} from "@/lib/personal-entries";

const sessionCookie = "wat_session";

function userIdFromRequest(request: NextRequest): string | null {
  return request.cookies.get(sessionCookie)?.value.trim() || null;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string" && item.trim());
}

function isPersonalEntry(value: unknown): value is PersonalEntry {
  if (!value || typeof value !== "object") return false;
  const entry = value as Partial<PersonalEntry>;

  return (
    typeof entry.id === "string" &&
    typeof entry.term === "string" &&
    typeof entry.expansion === "string" &&
    typeof entry.meaning === "string" &&
    isStringArray(entry.domains) &&
    Array.isArray(entry.sources)
  );
}

export function GET(request: NextRequest) {
  const userId = userIdFromRequest(request);
  if (!userId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }

  return NextResponse.json({ entries: getPersonalEntries(userId) });
}

export async function POST(request: NextRequest) {
  const userId = userIdFromRequest(request);
  if (!userId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }

  const body = (await request.json()) as unknown;
  if (!isPersonalEntry(body)) {
    return apiErrorResponse(request, "invalid_personal_entry", 400, {
      message: "invalid personal entry"
    });
  }

  try {
    return NextResponse.json({ entry: createPersonalEntry(userId, body) });
  } catch (error) {
    return apiErrorResponse(request, "personal_entry_conflict", 409, {
      message: error instanceof Error ? error.message : "create failed"
    });
  }
}

export async function PATCH(request: NextRequest) {
  const userId = userIdFromRequest(request);
  if (!userId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }

  const body = (await request.json()) as { id?: unknown; patch?: unknown };
  if (typeof body.id !== "string" || !body.patch || typeof body.patch !== "object") {
    return apiErrorResponse(request, "invalid_personal_entry_update", 400, {
      message: "invalid personal entry update"
    });
  }

  try {
    return NextResponse.json({
      entry: updatePersonalEntry(userId, body.id, body.patch as Partial<PersonalEntry>)
    });
  } catch (error) {
    return apiErrorResponse(request, "personal_entry_not_found", 404, {
      message: error instanceof Error ? error.message : "update failed"
    });
  }
}

export async function DELETE(request: NextRequest) {
  const userId = userIdFromRequest(request);
  if (!userId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }

  const id = request.nextUrl.searchParams.get("id");
  if (!id) {
    return apiErrorResponse(request, "missing_id", 400, { message: "id is required" });
  }

  try {
    return NextResponse.json({ entry: deletePersonalEntry(userId, id) });
  } catch (error) {
    return apiErrorResponse(request, "personal_entry_not_found", 404, {
      message: error instanceof Error ? error.message : "delete failed"
    });
  }
}
