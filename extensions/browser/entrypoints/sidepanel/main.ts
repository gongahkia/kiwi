import {
  sidePanelQueryStorageKey,
  type LookupResponse,
  type SidePanelQuery
} from "../../src/messages.js";

interface SearchEntry {
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

const pageContext = byId<HTMLParagraphElement>("page-context");
const form = byId<HTMLFormElement>("search-form");
const query = byId<HTMLInputElement>("query");
const results = byId<HTMLElement>("results");

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

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const term = query.value.trim();
  if (term) void search(term);
});

void consumeQueuedLookup();
