import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { recordAuditLog } from "@/lib/audit-log";
import {
  createPersonalEntry,
  deletePersonalEntry,
  getPersonalEntries,
  updatePersonalEntry,
  type PersonalEntry
} from "@/lib/personal-entries";
import { sessionUserFromRequest } from "@/lib/session";

async function userIdFromRequest(request: NextRequest): Promise<string | null> {
  return (await sessionUserFromRequest(request))?.id ?? null;
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
    (entry.contemporaries === undefined || isStringArray(entry.contemporaries)) &&
    Array.isArray(entry.sources)
  );
}

export async function GET(request: NextRequest) {
  const userId = await userIdFromRequest(request);
  if (!userId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }

  return NextResponse.json({ entries: await getPersonalEntries(userId) });
}

export async function POST(request: NextRequest) {
  const userId = await userIdFromRequest(request);
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
    const entry = await createPersonalEntry(userId, body);
    await recordAuditLog({
      action: "personal_entry.create",
      actor_id: userId,
      after_jsonb: entry,
      before_jsonb: null,
      target_id: entry.id,
      target_type: "personal_entry",
      team_id: null
    });
    return NextResponse.json({ entry });
  } catch (error) {
    return apiErrorResponse(request, "personal_entry_conflict", 409, {
      message: error instanceof Error ? error.message : "create failed"
    });
  }
}

export async function PATCH(request: NextRequest) {
  const userId = await userIdFromRequest(request);
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
    const before = (await getPersonalEntries(userId)).find((entry) => entry.id === body.id);
    if (!before) throw new Error("personal entry not found");
    const entry = await updatePersonalEntry(userId, body.id, body.patch as Partial<PersonalEntry>);
    await recordAuditLog({
      action: "personal_entry.update",
      actor_id: userId,
      after_jsonb: entry,
      before_jsonb: before,
      target_id: entry.id,
      target_type: "personal_entry",
      team_id: null
    });
    return NextResponse.json({ entry });
  } catch (error) {
    return apiErrorResponse(request, "personal_entry_not_found", 404, {
      message: error instanceof Error ? error.message : "update failed"
    });
  }
}

export async function DELETE(request: NextRequest) {
  const userId = await userIdFromRequest(request);
  if (!userId) {
    return apiErrorResponse(request, "login_required", 401, { message: "login required" });
  }

  const id = request.nextUrl.searchParams.get("id");
  if (!id) {
    return apiErrorResponse(request, "missing_id", 400, { message: "id is required" });
  }
  if (request.nextUrl.searchParams.get("confirm") !== id) {
    return apiErrorResponse(request, "confirmation_required", 400, {
      message: "confirmation required"
    });
  }

  try {
    const entry = await deletePersonalEntry(userId, id);
    await recordAuditLog({
      action: "personal_entry.deprecate",
      actor_id: userId,
      after_jsonb: { deprecated: true, deprecated_reason: "user removed" },
      before_jsonb: entry,
      target_id: entry.id,
      target_type: "personal_entry",
      team_id: null
    });
    return NextResponse.json({ entry });
  } catch (error) {
    return apiErrorResponse(request, "personal_entry_not_found", 404, {
      message: error instanceof Error ? error.message : "delete failed"
    });
  }
}
