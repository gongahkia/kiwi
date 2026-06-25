import { randomUUID } from "node:crypto";

import { NextResponse, type NextRequest } from "next/server";

import { apiErrorResponse } from "@/lib/api-error";
import { corsHeadersForRequest } from "@/lib/cors";
import { hasApiScope, resolveApiIdentity } from "@/lib/api-identity";
import {
  createPersonalEntry,
  getPersonalEntries,
  updatePersonalEntry
} from "@/lib/personal-entries";
import {
  createTeamEntry,
  getTeamEntries,
  updateTeamEntry,
  type TeamEntry,
  type TeamEntrySource
} from "@/lib/team-entries";
import { checkWriteRateLimit } from "@/lib/write-rate-limit";

export const runtime = "nodejs";

type CustomEntryScope = "personal" | "team";
type CustomEntryMode = "create" | "upsert";

interface CustomEntryRequest {
  domains?: unknown;
  expansion?: unknown;
  meaning?: unknown;
  mode?: unknown;
  scope?: unknown;
  sourceTitle?: unknown;
  sourceUrl?: unknown;
  term?: unknown;
}

function json(request: NextRequest, body: unknown, init?: ResponseInit) {
  const headers = new Headers(init?.headers);
  corsHeadersForRequest(request, { methods: "POST, OPTIONS" }).forEach((value, key) =>
    headers.set(key, value)
  );

  return NextResponse.json(body, { ...init, headers });
}

function asNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function domainsFromBody(value: unknown, fallbackDomain: string | null): string[] {
  const domains = Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string" && Boolean(item.trim()))
    : [];
  const cleaned = domains.map((domain) => domain.trim().toLowerCase());
  if (fallbackDomain) cleaned.push(fallbackDomain.toLowerCase());

  const unique = Array.from(new Set(cleaned)).slice(0, 12);
  return unique.length > 0 ? unique : ["custom"];
}

function hostnameFromUrl(value: string | null): string | null {
  if (!value) return null;
  try {
    return new URL(value).hostname || null;
  } catch {
    return null;
  }
}

function sourceUrl(value: string | null, id: string): string {
  if (!value) return `https://wat.local/custom/${id}`;
  try {
    return new URL(value).toString();
  } catch {
    return `https://wat.local/custom/${id}`;
  }
}

function makeSource(
  body: CustomEntryRequest,
  id: string,
  scope: CustomEntryScope,
  term: string,
  expansion: string
): TeamEntrySource {
  const url = sourceUrl(asNonEmptyString(body.sourceUrl), id);
  const title =
    asNonEmptyString(body.sourceTitle) ?? hostnameFromUrl(url) ?? "Browser custom entry";

  return {
    license: scope === "team" ? "proprietary-team" : "proprietary-personal",
    publisher: "wat browser extension",
    retrieved_at: new Date().toISOString(),
    snippet: `${term} was saved as ${expansion} from the browser extension.`,
    title,
    url
  };
}

function customEntryFromBody(
  body: CustomEntryRequest
): { entry: TeamEntry; mode: CustomEntryMode; scope: CustomEntryScope } | null {
  const term = asNonEmptyString(body.term);
  const expansion = asNonEmptyString(body.expansion);
  if (!term || !expansion) return null;
  if (body.mode != null && body.mode !== "create" && body.mode !== "upsert") return null;

  const mode: CustomEntryMode = body.mode === "upsert" ? "upsert" : "create";
  const scope: CustomEntryScope = body.scope === "team" ? "team" : "personal";
  const id = `custom-${scope}-${randomUUID()}`;
  const meaning = asNonEmptyString(body.meaning) ?? `Custom definition for ${term}.`;
  const fallbackDomain = hostnameFromUrl(asNonEmptyString(body.sourceUrl));

  return {
    entry: {
      domains: domainsFromBody(body.domains, fallbackDomain),
      expansion,
      id,
      meaning,
      sources: [makeSource(body, id, scope, term, expansion)],
      term
    },
    mode,
    scope
  };
}

function entryKey(entry: Pick<TeamEntry, "expansion" | "term">): string {
  return `${entry.term.trim().toLowerCase()}:${entry.expansion.trim().toLowerCase()}`;
}

function withEntryId(entry: TeamEntry, id: string): TeamEntry {
  return {
    ...entry,
    id,
    sources: entry.sources.map((source) => {
      try {
        const url = new URL(source.url);
        if (url.hostname !== "wat.local") return source;
      } catch {
        return source;
      }

      return { ...source, url: `https://wat.local/custom/${id}` };
    })
  };
}

async function upsertTeamEntry(
  teamId: string,
  entry: TeamEntry
): Promise<{ entry: TeamEntry; status: "created" | "updated" }> {
  const existing = (await getTeamEntries(teamId)).find(
    (item) => entryKey(item) === entryKey(entry)
  );
  if (!existing) {
    return { entry: await createTeamEntry(teamId, entry), status: "created" };
  }

  return {
    entry: await updateTeamEntry(teamId, existing.id, withEntryId(entry, existing.id)),
    status: "updated"
  };
}

async function upsertPersonalEntry(
  userId: string,
  entry: TeamEntry
): Promise<{ entry: TeamEntry; status: "created" | "updated" }> {
  const existing = (await getPersonalEntries(userId)).find(
    (item) => entryKey(item) === entryKey(entry)
  );
  if (!existing) {
    return { entry: await createPersonalEntry(userId, entry), status: "created" };
  }

  return {
    entry: await updatePersonalEntry(userId, existing.id, withEntryId(entry, existing.id)),
    status: "updated"
  };
}

export function OPTIONS(request: NextRequest) {
  return new NextResponse(null, {
    headers: corsHeadersForRequest(request, { methods: "POST, OPTIONS" }),
    status: 204
  });
}

export async function POST(request: NextRequest) {
  const identity = await resolveApiIdentity(request.headers);
  if (!identity.ok) {
    return apiErrorResponse(request, identity.error, identity.status, {
      headers: corsHeadersForRequest(request, { methods: "POST, OPTIONS" })
    });
  }
  const userId = request.headers.get("x-wat-user-id")?.trim();
  if (identity.identity.type !== "api" || !userId) {
    return apiErrorResponse(request, "missing_user_scope", 401, {
      headers: corsHeadersForRequest(request, { methods: "POST, OPTIONS" }),
      message: "api token and x-wat-user-id are required"
    });
  }
  if (!hasApiScope(identity.identity, "write")) {
    return apiErrorResponse(request, "insufficient_api_scope", 403, {
      headers: corsHeadersForRequest(request, { methods: "POST, OPTIONS" }),
      message: "write scope is required"
    });
  }
  const writeLimit = await checkWriteRateLimit("custom-entry", identity.identity.teamId ?? userId);
  if (!writeLimit.allowed) {
    return apiErrorResponse(request, "rate_limited", 429, {
      fields: {
        limit: writeLimit.limit,
        remaining: writeLimit.remaining,
        reset_at: writeLimit.reset_at
      },
      headers: corsHeadersForRequest(request, { methods: "POST, OPTIONS" }),
      message: "rate limit exceeded"
    });
  }

  const parsed = customEntryFromBody((await request.json()) as CustomEntryRequest);
  if (!parsed) {
    return apiErrorResponse(request, "invalid_custom_entry", 400, {
      headers: corsHeadersForRequest(request, { methods: "POST, OPTIONS" }),
      message: "term, expansion, and valid mode are required"
    });
  }

  if (parsed.scope === "team" && !identity.identity.teamId) {
    return apiErrorResponse(request, "missing_team_scope", 403, {
      headers: corsHeadersForRequest(request, { methods: "POST, OPTIONS" }),
      message: "x-wat-team-id is required for team entries"
    });
  }

  try {
    if (parsed.mode === "upsert") {
      const result =
        parsed.scope === "team"
          ? await upsertTeamEntry(identity.identity.teamId!, parsed.entry)
          : await upsertPersonalEntry(userId, parsed.entry);

      return json(
        request,
        { entry: result.entry, mode: result.status, scope: parsed.scope },
        { status: result.status === "created" ? 201 : 200 }
      );
    }

    const entry =
      parsed.scope === "team"
        ? await createTeamEntry(identity.identity.teamId!, parsed.entry)
        : await createPersonalEntry(userId, parsed.entry);

    return json(request, { entry, mode: "created", scope: parsed.scope }, { status: 201 });
  } catch (error) {
    return apiErrorResponse(request, "custom_entry_conflict", 409, {
      headers: corsHeadersForRequest(request, { methods: "POST, OPTIONS" }),
      message: error instanceof Error ? error.message : "create failed"
    });
  }
}
