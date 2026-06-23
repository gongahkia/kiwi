import { type SaveCustomEntryMessage, type SaveCustomEntryResponse } from "./messages.js";
import { apiErrorFromResponse, apiErrorResult, offlineApiError } from "./api-errors.js";
import { authHeaders } from "./lookup-service.js";
import { loadWatOptions, type WatOptions } from "./options.js";

interface SaveCustomEntryDeps {
  fetchSaveCustomEntry?: (message: SaveCustomEntryMessage, options: WatOptions) => Promise<unknown>;
  loadOptions?: () => Promise<WatOptions>;
}

function cleanDomains(domains: string[] | undefined): string[] {
  return Array.from(
    new Set((domains ?? []).map((domain) => domain.trim().toLowerCase()).filter(Boolean))
  );
}

export function saveCustomEntryPayload(message: SaveCustomEntryMessage): Record<string, unknown> {
  return {
    domains: cleanDomains(message.domains),
    expansion: message.expansion.trim(),
    meaning: message.meaning?.trim() || undefined,
    scope: message.scope ?? "personal",
    sourceTitle: message.sourceTitle?.trim() || undefined,
    sourceUrl: message.sourceUrl?.trim() || undefined,
    term: message.term.trim()
  };
}

export async function fetchSaveCustomEntry(
  message: SaveCustomEntryMessage,
  options: WatOptions
): Promise<unknown> {
  const url = new URL("/api/v1/custom-entries", options.apiBaseUrl);
  const headers = authHeaders(options);
  headers.set("content-type", "application/json");

  let response: Response;
  try {
    response = await fetch(url, {
      body: JSON.stringify(saveCustomEntryPayload(message)),
      credentials: "include",
      headers,
      method: "POST"
    });
  } catch {
    throw offlineApiError("save");
  }
  if (!response.ok) {
    throw await apiErrorFromResponse("save", response);
  }

  return response.json() as Promise<unknown>;
}

export async function handleSaveCustomEntry(
  message: SaveCustomEntryMessage,
  deps: SaveCustomEntryDeps = {}
): Promise<SaveCustomEntryResponse> {
  const load = deps.loadOptions ?? loadWatOptions;
  const requestSave = deps.fetchSaveCustomEntry ?? fetchSaveCustomEntry;

  if (!message.term.trim() || !message.expansion.trim()) {
    return { error: "term and expansion are required", ok: false };
  }

  try {
    const body = await requestSave(message, await load());
    return { body, ok: true };
  } catch (error) {
    return apiErrorResult(error, "save failed") as SaveCustomEntryResponse;
  }
}
