import { NextResponse, type NextRequest } from "next/server";

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

function unauthorized() {
  return NextResponse.json({ error: "login required" }, { status: 401 });
}

export function GET(request: NextRequest) {
  const userId = userIdFromRequest(request);
  if (!userId) return unauthorized();

  return NextResponse.json({ entries: getPersonalEntries(userId) });
}

export async function POST(request: NextRequest) {
  const userId = userIdFromRequest(request);
  if (!userId) return unauthorized();

  const body = (await request.json()) as unknown;
  if (!isPersonalEntry(body)) {
    return NextResponse.json({ error: "invalid personal entry" }, { status: 400 });
  }

  try {
    return NextResponse.json({ entry: createPersonalEntry(userId, body) });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "create failed" },
      { status: 409 }
    );
  }
}

export async function PATCH(request: NextRequest) {
  const userId = userIdFromRequest(request);
  if (!userId) return unauthorized();

  const body = (await request.json()) as { id?: unknown; patch?: unknown };
  if (typeof body.id !== "string" || !body.patch || typeof body.patch !== "object") {
    return NextResponse.json({ error: "invalid personal entry update" }, { status: 400 });
  }

  try {
    return NextResponse.json({
      entry: updatePersonalEntry(userId, body.id, body.patch as Partial<PersonalEntry>)
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "update failed" },
      { status: 404 }
    );
  }
}

export async function DELETE(request: NextRequest) {
  const userId = userIdFromRequest(request);
  if (!userId) return unauthorized();

  const id = request.nextUrl.searchParams.get("id");
  if (!id) {
    return NextResponse.json({ error: "id is required" }, { status: 400 });
  }

  try {
    return NextResponse.json({ entry: deletePersonalEntry(userId, id) });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "delete failed" },
      { status: 404 }
    );
  }
}
