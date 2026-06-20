import { randomUUID } from "node:crypto";

import { NextResponse, type NextRequest } from "next/server";

import { resolveApiIdentity } from "@/lib/api-identity";
import { createPersonalEntry } from "@/lib/personal-entries";
import { createTeamEntry, type TeamEntry, type TeamEntrySource } from "@/lib/team-entries";

export const runtime = "nodejs";

type CustomEntryScope = "personal" | "team";

interface CustomEntryRequest {
  domains?: unknown;
  expansion?: unknown;
  meaning?: unknown;
  scope?: unknown;
  sourceTitle?: unknown;
  sourceUrl?: unknown;
  term?: unknown;
}

function corsHeaders() {
  return {
    "access-control-allow-headers":
      "authorization, content-type, x-api-key, x-wat-team-id, x-wat-user-id",
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-origin": "*"
  };
}

function json(body: unknown, init?: ResponseInit) {
  const headers = new Headers(init?.headers);
  for (const [key, value] of Object.entries(corsHeaders())) {
    headers.set(key, value);
  }

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

  return Array.from(new Set(cleaned)).slice(0, 12);
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
  term: string,
  expansion: string
): TeamEntrySource {
  const url = sourceUrl(asNonEmptyString(body.sourceUrl), id);
  const title =
    asNonEmptyString(body.sourceTitle) ?? hostnameFromUrl(url) ?? "Browser custom entry";

  return {
    license: "MIT",
    publisher: "wat browser extension",
    retrieved_at: new Date().toISOString(),
    snippet: `${term} was saved as ${expansion} from the browser extension.`,
    title,
    url
  };
}

function customEntryFromBody(
  body: CustomEntryRequest
): { entry: TeamEntry; scope: CustomEntryScope } | null {
  const term = asNonEmptyString(body.term);
  const expansion = asNonEmptyString(body.expansion);
  if (!term || !expansion) return null;

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
      sources: [makeSource(body, id, term, expansion)],
      term
    },
    scope
  };
}

export function OPTIONS() {
  return new NextResponse(null, { headers: corsHeaders(), status: 204 });
}

export async function POST(request: NextRequest) {
  const identity = resolveApiIdentity(request.headers);
  if (!identity.ok) {
    return json({ error: identity.error }, { status: identity.status });
  }
  if (identity.identity.type !== "api" || !identity.identity.userId) {
    return json({ error: "api token and x-wat-user-id are required" }, { status: 401 });
  }

  const parsed = customEntryFromBody((await request.json()) as CustomEntryRequest);
  if (!parsed) {
    return json({ error: "term and expansion are required" }, { status: 400 });
  }

  if (parsed.scope === "team" && !identity.identity.teamId) {
    return json({ error: "x-wat-team-id is required for team entries" }, { status: 403 });
  }

  try {
    const entry =
      parsed.scope === "team"
        ? createTeamEntry(parsed.entry)
        : createPersonalEntry(identity.identity.userId, parsed.entry);

    return json({ entry, scope: parsed.scope }, { status: 201 });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : "create failed" },
      { status: 409 }
    );
  }
}
