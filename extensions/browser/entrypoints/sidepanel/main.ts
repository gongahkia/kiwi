import {
  sidePanelCustomEntryStorageKey,
  sidePanelQueryStorageKey,
  type LookupResponse,
  type SaveCustomEntryResponse,
  type SidePanelCustomEntryDraft,
  type SidePanelQuery
} from "../../src/messages.js";
import { listAlternatives } from "../../src/alternatives.js";

interface SearchEntry {
  contemporaries?: string[];
  expansions?: string[];
  meaning_short?: string;
  sources?: Array<{ title?: string; url?: string }>;
  term?: string;
}

interface SearchBody {
  matches?: Array<{ entry?: SearchEntry }>;
}

type BrowserTab = Awaited<ReturnType<typeof browser.tabs.query>>[number];

function byId<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`missing #${id}`);
  return element as T;
}

function contextFromTab(tab: BrowserTab | undefined): string {
  if (!tab?.url) return "";
  try {
    const url = new URL(tab.url);
    return url.hostname || tab.url;
  } catch {
    return tab.url;
  }
}

function resultEntries(body: unknown): SearchEntry[] {
  const searchBody = body as SearchBody;
  return searchBody.matches?.flatMap((match) => (match.entry ? [match.entry] : [])) ?? [];
}

function domainFromContext(context: string): string[] {
  const domain = context.trim().toLowerCase();
  return domain ? [domain] : [];
}

function sourceUrlFromContext(context: string): string | undefined {
  if (/^https?:\/\//i.test(context)) return context;
  return currentDraft?.sourceUrl;
}

function sourcePreviewText(draft: SidePanelCustomEntryDraft): string | null {
  const title = draft.sourceTitle?.trim();
  const url = draft.sourceUrl?.trim();
  if (title && url) return `Source: ${title} - ${url}`;
  if (title) return `Source: ${title}`;
  if (url) return `Source: ${url}`;
  return null;
}

function fillSaveDraft(draft: SidePanelCustomEntryDraft) {
  currentDraft = draft;
  saveTerm.value = draft.term;
  const preview = sourcePreviewText(draft);
  saveSourcePreview.hidden = !preview;
  saveSourcePreview.textContent = preview ?? "";
  saveStatus.textContent = `Ready to save from ${draft.context || "this page"}.`;
}

const pageContext = byId<HTMLParagraphElement>("page-context");
const form = byId<HTMLFormElement>("search-form");
const query = byId<HTMLInputElement>("query");
const results = byId<HTMLElement>("results");
const saveForm = byId<HTMLFormElement>("save-form");
const saveTerm = byId<HTMLInputElement>("save-term");
const saveExpansion = byId<HTMLInputElement>("save-expansion");
const saveMeaning = byId<HTMLTextAreaElement>("save-meaning");
const saveScope = byId<HTMLSelectElement>("save-scope");
const saveSourcePreview = byId<HTMLParagraphElement>("save-source-preview");
const saveStatus = byId<HTMLParagraphElement>("save-status");
let currentDraft: SidePanelCustomEntryDraft | null = null;

async function activeContext(): Promise<string> {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  const context = contextFromTab(tab);
  pageContext.textContent = context;
  return context;
}

function renderEntries(entries: SearchEntry[]) {
  results.replaceChildren();
  if (entries.length === 0) {
    results.textContent = "No results.";
    return;
  }

  for (const entry of entries) {
    const article = document.createElement("article");
    article.className = "result";

    const title = document.createElement("strong");
    title.textContent = `${entry.term ?? "TERM"} - ${entry.expansions?.[0] ?? "Expansion"}`;
    article.append(title);

    if (entry.meaning_short) {
      const meaning = document.createElement("div");
      meaning.textContent = entry.meaning_short;
      article.append(meaning);
    }

    const alternatives = listAlternatives(entry.contemporaries);
    if (alternatives.length > 0) {
      const section = document.createElement("div");
      section.className = "alternatives";

      const label = document.createElement("span");
      label.textContent = "Alternatives:";
      section.append(label);

      for (const alternative of alternatives) {
        const button = document.createElement("button");
        button.className = "alternative-link";
        button.type = "button";
        button.textContent = alternative;
        button.addEventListener("click", () => {
          query.value = alternative;
          void search(alternative);
        });
        section.append(button);
      }

      article.append(section);
    }

    const source = entry.sources?.[0];
    if (source?.url) {
      const meta = document.createElement("div");
      meta.className = "meta";
      meta.textContent = source.title ? `${source.title} - ${source.url}` : source.url;
      article.append(meta);
    }

    results.append(article);
  }
}

async function search(term: string, queuedContext?: string) {
  results.textContent = "Searching...";
  const context = queuedContext ?? (await activeContext());
  pageContext.textContent = context;
  const response = (await browser.runtime.sendMessage({
    context,
    limit: 5,
    term,
    type: "wat.lookup"
  })) as LookupResponse;

  if (!response.ok) {
    results.textContent = response.error;
    return;
  }

  renderEntries(resultEntries(response.body));
}

async function consumeQueuedLookup() {
  const stored = (await browser.storage.local.get(sidePanelQueryStorageKey)) as Record<
    string,
    SidePanelQuery | undefined
  >;
  const pending = stored[sidePanelQueryStorageKey];
  if (!pending?.term) {
    await activeContext();
    return;
  }

  query.value = pending.term;
  await browser.storage.local.remove(sidePanelQueryStorageKey);
  await search(pending.term, pending.context);
}

async function consumeCustomEntryDraft() {
  const stored = (await browser.storage.local.get(sidePanelCustomEntryStorageKey)) as Record<
    string,
    SidePanelCustomEntryDraft | undefined
  >;
  const pending = stored[sidePanelCustomEntryStorageKey];
  if (!pending?.term) return;

  fillSaveDraft(pending);
  await browser.storage.local.remove(sidePanelCustomEntryStorageKey);
}

async function saveCustomEntry() {
  const context = currentDraft?.context ?? (await activeContext());
  saveStatus.textContent = "Saving...";
  const response = (await browser.runtime.sendMessage({
    domains: domainFromContext(context),
    expansion: saveExpansion.value,
    meaning: saveMeaning.value,
    scope: saveScope.value === "team" ? "team" : "personal",
    sourceTitle: currentDraft?.sourceTitle ?? document.title,
    sourceUrl: sourceUrlFromContext(context),
    term: saveTerm.value,
    type: "wat.customEntry.save"
  })) as SaveCustomEntryResponse;

  if (!response.ok) {
    saveStatus.textContent = response.error;
    return;
  }

  saveStatus.textContent = "Saved. Future searches will include this custom layer.";
  saveExpansion.value = "";
  saveMeaning.value = "";
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const term = query.value.trim();
  if (term) void search(term);
});

saveForm.addEventListener("submit", (event) => {
  event.preventDefault();
  if (saveTerm.value.trim() && saveExpansion.value.trim()) void saveCustomEntry();
});

void consumeQueuedLookup().then(() => consumeCustomEntryDraft());
