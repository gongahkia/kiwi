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

export async function loadWatOptions(): Promise<WatOptions> {
  const stored = (await browser.storage.local.get(optionsStorageKey)) as Record<
    string,
    Partial<WatOptions>
  >;
  return { ...defaultOptions, ...(stored[optionsStorageKey] ?? {}) };
}
