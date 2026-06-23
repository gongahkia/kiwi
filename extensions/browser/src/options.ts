export interface WatOptions {
  accountEmail: string;
  apiBaseUrl: string;
  apiToken: string;
  domainFilters: string[];
  teamId: string;
  highlightMode: boolean;
  hoverMode: boolean;
}

export const optionsStorageKey = "watOptions";

export const defaultOptions: WatOptions = {
  accountEmail: "",
  apiBaseUrl: "http://localhost:3000",
  apiToken: "",
  domainFilters: [],
  teamId: "",
  highlightMode: false,
  hoverMode: false
};

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
  const stored = (await browser.storage.local.get(optionsStorageKey)) as Record<
    string,
    Partial<WatOptions>
  >;
  return { ...defaultOptions, ...(stored[optionsStorageKey] ?? {}) };
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
