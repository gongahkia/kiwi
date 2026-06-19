interface WatOptions {
  accountEmail: string;
  apiBaseUrl: string;
  apiToken: string;
  domainFilters: string[];
  hoverMode: boolean;
}

const storageKey = "watOptions";
const defaultOptions: WatOptions = {
  accountEmail: "",
  apiBaseUrl: "http://localhost:3000",
  apiToken: "",
  domainFilters: [],
  hoverMode: false
};

function byId<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) {
    throw new Error(`missing #${id}`);
  }

  return element as T;
}

function parseDomainFilters(value: string): string[] {
  return value
    .split(",")
    .map((domain) => domain.trim().toLowerCase())
    .filter(Boolean);
}

function domainFilterText(filters: string[]): string {
  return filters.join(", ");
}

const form = byId<HTMLFormElement>("options-form");
const apiBaseUrl = byId<HTMLInputElement>("api-base-url");
const accountEmail = byId<HTMLInputElement>("account-email");
const apiToken = byId<HTMLInputElement>("api-token");
const hoverMode = byId<HTMLInputElement>("hover-mode");
const domainFilters = byId<HTMLInputElement>("domain-filters");
const status = byId<HTMLSpanElement>("status");

function renderOptions(options: WatOptions) {
  apiBaseUrl.value = options.apiBaseUrl;
  accountEmail.value = options.accountEmail;
  apiToken.value = options.apiToken;
  hoverMode.checked = options.hoverMode;
  domainFilters.value = domainFilterText(options.domainFilters);
}

function optionsFromForm(): WatOptions {
  return {
    accountEmail: accountEmail.value.trim(),
    apiBaseUrl: apiBaseUrl.value.trim() || defaultOptions.apiBaseUrl,
    apiToken: apiToken.value.trim(),
    domainFilters: parseDomainFilters(domainFilters.value),
    hoverMode: hoverMode.checked
  };
}

async function loadOptions() {
  const stored = (await browser.storage.local.get(storageKey)) as Record<
    string,
    Partial<WatOptions>
  >;
  renderOptions({ ...defaultOptions, ...(stored[storageKey] ?? {}) });
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const options = optionsFromForm();
  void browser.storage.local.set({ [storageKey]: options }).then(() => {
    status.textContent = "Saved";
  });
});

void loadOptions();
