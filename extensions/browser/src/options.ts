export interface WatOptions {
  accountEmail: string;
  apiBaseUrl: string;
  apiToken: string;
  domainFilters: string[];
  teamId: string;
  teams: WatTeamOption[];
  heatmapMode: boolean;
  highlightMode: boolean;
  hoverMode: boolean;
}

export interface WatTeamOption {
  id: string;
  name: string;
}

export const optionsStorageKey = "watOptions";

export const defaultOptions: WatOptions = {
  accountEmail: "",
  apiBaseUrl: "http://localhost:3000",
  apiToken: "",
  domainFilters: [],
  teamId: "",
  teams: [],
  heatmapMode: false,
  highlightMode: false,
  hoverMode: false
};

type ManagedOptionKey =
  | "apiBaseUrl"
  | "domainFilters"
  | "heatmapMode"
  | "highlightMode"
  | "hoverMode"
  | "teamId"
  | "teams";
type ManagedOptions = Pick<WatOptions, ManagedOptionKey>;

interface ManagedStorageArea {
  get: (keys?: readonly ManagedOptionKey[] | null) => Promise<Record<string, unknown>>;
}

function cleanString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function cleanDomainFilters(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const domains = value
    .filter((domain): domain is string => typeof domain === "string")
    .map((domain) => domain.trim().toLowerCase())
    .filter(Boolean);

  return Array.from(new Set(domains));
}

function cleanBoolean(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
}

export function cleanTeamOptions(value: unknown): WatTeamOption[] {
  if (!Array.isArray(value)) return [];
  const teams = new Map<string, WatTeamOption>();
  for (const item of value) {
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    const id = cleanString(record.id);
    if (!id) continue;
    teams.set(id, { id, name: cleanString(record.name) ?? id });
  }
  return Array.from(teams.values()).sort((left, right) => left.name.localeCompare(right.name));
}

export function upsertTeamOption(teams: WatTeamOption[], team: WatTeamOption): WatTeamOption[] {
  return cleanTeamOptions([
    ...teams.filter((item) => item.id !== team.id),
    { id: team.id.trim(), name: team.name.trim() || team.id.trim() }
  ]);
}

export function managedOptionsFromPolicy(policy: Record<string, unknown>): Partial<ManagedOptions> {
  const apiBaseUrl = cleanString(policy.apiBaseUrl);
  const domainFilters = cleanDomainFilters(policy.domainFilters);
  const heatmapMode = cleanBoolean(policy.heatmapMode);
  const highlightMode = cleanBoolean(policy.highlightMode);
  const hoverMode = cleanBoolean(policy.hoverMode);
  const teamId = cleanString(policy.teamId);
  const teams = cleanTeamOptions(policy.teams);

  return {
    ...(apiBaseUrl ? { apiBaseUrl } : {}),
    ...(domainFilters ? { domainFilters } : {}),
    ...(heatmapMode == null ? {} : { heatmapMode }),
    ...(highlightMode == null ? {} : { highlightMode }),
    ...(hoverMode == null ? {} : { hoverMode }),
    ...(teamId ? { teamId } : {}),
    ...(teams.length > 0 ? { teams } : {})
  };
}

async function loadManagedWatOptions(): Promise<Partial<ManagedOptions>> {
  const storage = browser.storage as typeof browser.storage & { managed?: ManagedStorageArea };
  if (!storage.managed) return {};

  try {
    return managedOptionsFromPolicy(await storage.managed.get(null));
  } catch {
    return {};
  }
}

export interface WatConnectionTestResult {
  message: string;
  ok: boolean;
}

type FetchLike = (
  input: string | URL,
  init?: {
    headers?: Headers;
  }
) => Promise<Pick<Response, "json" | "ok" | "status">>;

export async function loadWatOptions(): Promise<WatOptions> {
  const local = await loadLocalWatOptions();
  const managed = await loadManagedWatOptions();
  return { ...local, ...managed };
}

export async function loadLocalWatOptions(): Promise<WatOptions> {
  const stored = (await browser.storage.local.get(optionsStorageKey)) as Record<
    string,
    Partial<WatOptions>
  >;
  return normalizeWatOptions(stored[optionsStorageKey] ?? {});
}

export function normalizeWatOptions(options: Partial<WatOptions>): WatOptions {
  return {
    ...defaultOptions,
    ...options,
    accountEmail: cleanString(options.accountEmail) ?? "",
    apiBaseUrl: cleanString(options.apiBaseUrl) ?? defaultOptions.apiBaseUrl,
    apiToken: cleanString(options.apiToken) ?? "",
    domainFilters: cleanDomainFilters(options.domainFilters) ?? [],
    heatmapMode: cleanBoolean(options.heatmapMode) ?? defaultOptions.heatmapMode,
    highlightMode: cleanBoolean(options.highlightMode) ?? defaultOptions.highlightMode,
    hoverMode: cleanBoolean(options.hoverMode) ?? defaultOptions.hoverMode,
    teamId: cleanString(options.teamId) ?? "",
    teams: cleanTeamOptions(options.teams)
  };
}

export async function testWatConnection(
  options: WatOptions,
  fetchImpl: FetchLike = fetch
): Promise<WatConnectionTestResult> {
  let url: URL;
  try {
    url = new URL("/api/v1/search", options.apiBaseUrl);
  } catch {
    return { message: "Connection failed: invalid API base URL.", ok: false };
  }

  url.searchParams.set("q", "API");
  url.searchParams.set("limit", "1");
  const headers = new Headers();
  if (options.apiToken) headers.set("authorization", `Bearer ${options.apiToken}`);
  if (options.accountEmail) headers.set("x-wat-user-id", options.accountEmail);
  if (options.teamId) headers.set("x-wat-team-id", options.teamId);

  try {
    const response = await fetchImpl(url, { headers });
    if (!response.ok) {
      return {
        message:
          response.status === 401
            ? "Connection failed: unauthorized API token."
            : `Connection failed: HTTP ${response.status}.`,
        ok: false
      };
    }

    const body = (await response.json()) as { matches?: unknown };
    if (!Array.isArray(body.matches)) {
      return { message: "Connection failed: unexpected API response.", ok: false };
    }

    return { message: "Connection verified. Saved.", ok: true };
  } catch {
    return { message: "Connection failed: API is unreachable.", ok: false };
  }
}
