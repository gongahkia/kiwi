import {
  defaultOptions,
  loadWatOptions,
  optionsStorageKey,
  testWatConnection,
  upsertTeamOption,
  type WatOptions
} from "../../src/options.js";

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
const teamId = byId<HTMLInputElement>("team-id");
const teamPicker = byId<HTMLSelectElement>("team-picker");
const addTeam = byId<HTMLButtonElement>("add-team");
const hoverMode = byId<HTMLInputElement>("hover-mode");
const highlightMode = byId<HTMLInputElement>("highlight-mode");
const heatmapMode = byId<HTMLInputElement>("heatmap-mode");
const domainFilters = byId<HTMLInputElement>("domain-filters");
const status = byId<HTMLSpanElement>("status");
let knownTeams: WatOptions["teams"] = [];

function renderOptions(options: WatOptions) {
  knownTeams = options.teams;
  apiBaseUrl.value = options.apiBaseUrl;
  accountEmail.value = options.accountEmail;
  apiToken.value = options.apiToken;
  teamId.value = options.teamId;
  renderTeamPicker(options);
  hoverMode.checked = options.hoverMode;
  highlightMode.checked = options.highlightMode;
  heatmapMode.checked = options.heatmapMode;
  domainFilters.value = domainFilterText(options.domainFilters);
}

function renderTeamPicker(options: WatOptions) {
  teamPicker.replaceChildren();
  teamPicker.append(new Option("No team", ""));
  const teams =
    options.teamId && !options.teams.some((team) => team.id === options.teamId)
      ? upsertTeamOption(options.teams, { id: options.teamId, name: options.teamId })
      : options.teams;
  for (const team of teams) {
    teamPicker.append(new Option(team.name, team.id));
  }
  teamPicker.value = options.teamId;
}

function optionsFromForm(): WatOptions {
  const selectedTeamId = teamPicker.value.trim() || teamId.value.trim();
  return {
    accountEmail: accountEmail.value.trim(),
    apiBaseUrl: apiBaseUrl.value.trim() || defaultOptions.apiBaseUrl,
    apiToken: apiToken.value.trim(),
    domainFilters: parseDomainFilters(domainFilters.value),
    teamId: selectedTeamId,
    teams: selectedTeamId
      ? upsertTeamOption(knownTeams, { id: selectedTeamId, name: selectedTeamId })
      : knownTeams,
    heatmapMode: heatmapMode.checked,
    highlightMode: highlightMode.checked,
    hoverMode: hoverMode.checked
  };
}

async function loadOptions() {
  renderOptions(await loadWatOptions());
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const options = optionsFromForm();
  status.textContent = "Testing connection...";
  void testWatConnection(options).then(async (result) => {
    if (!result.ok) {
      status.textContent = result.message;
      return;
    }

    await browser.storage.local.set({ [optionsStorageKey]: options });
    status.textContent = result.message;
  });
});

teamPicker.addEventListener("change", () => {
  teamId.value = teamPicker.value;
});

addTeam.addEventListener("click", () => {
  const id = teamId.value.trim();
  if (!id) {
    status.textContent = "Enter a team ID first.";
    return;
  }
  knownTeams = upsertTeamOption(knownTeams, { id, name: id });
  renderTeamPicker({ ...optionsFromForm(), teamId: id, teams: knownTeams });
  status.textContent = "Team added. Save to keep it.";
});

void loadOptions();
