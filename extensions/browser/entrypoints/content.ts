import { defineContentScript } from "wxt/utils/define-content-script";

import { acronymDensityForText, heatmapAlpha } from "../src/acronym-heatmap.js";
import { formatAlternativesLine } from "../src/alternatives.js";
import { type LookupResponse } from "../src/messages.js";
import { loadLocalWatOptions, type WatOptions } from "../src/options.js";

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

interface TextHit {
  node: Text;
  offset: number;
}

let activeToken = "";
let behaviorInstalled = false;
let heatmapInstalled = false;
let highlightInstalled = false;
let hoverTimer: number | undefined;
let tooltip: HTMLDivElement | null = null;
const heatmapElements = new Set<HTMLElement>();

function domainAllowed(filters: string[]): boolean {
  if (filters.length === 0) return true;
  return filters.some(
    (filter) => location.hostname === filter || location.hostname.endsWith(`.${filter}`)
  );
}

function timeout(ms: number): Promise<never> {
  return new Promise((_, reject) => {
    window.setTimeout(() => reject(new Error("options request timed out")), ms);
  });
}

async function loadContentOptions(): Promise<WatOptions> {
  try {
    return (await Promise.race([
      browser.runtime.sendMessage({ type: "wat.options.get" }),
      timeout(500)
    ])) as WatOptions;
  } catch {
    return loadLocalWatOptions();
  }
}

function setLookupListeners(enabled: boolean) {
  if (enabled && !behaviorInstalled) {
    document.addEventListener("mousemove", scheduleLookup, { passive: true });
    document.addEventListener("scroll", hideTooltip, { passive: true });
    behaviorInstalled = true;
  }
  if (!enabled && behaviorInstalled) {
    document.removeEventListener("mousemove", scheduleLookup);
    document.removeEventListener("scroll", hideTooltip);
    window.clearTimeout(hoverTimer);
    hideTooltip();
    behaviorInstalled = false;
  }
}

function applyOptions(options: WatOptions) {
  if (!domainAllowed(options.domainFilters)) {
    setLookupListeners(false);
    setHeatmap(false);
    return;
  }

  if (options.highlightMode && !highlightInstalled) {
    highlightAcronyms();
    highlightInstalled = true;
  }
  setHeatmap(options.heatmapMode);
  setLookupListeners(options.hoverMode || options.highlightMode);
}

function ensureTooltip(): HTMLDivElement {
  if (tooltip) return tooltip;

  const element = document.createElement("div");
  element.style.background = "#18181b";
  element.style.border = "1px solid #3f3f46";
  element.style.borderRadius = "6px";
  element.style.boxShadow = "0 8px 28px rgb(0 0 0 / 20%)";
  element.style.color = "#fff";
  element.style.font =
    '13px/1.4 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
  element.style.maxWidth = "320px";
  element.style.padding = "10px 12px";
  element.style.pointerEvents = "none";
  element.style.position = "fixed";
  element.style.zIndex = "2147483647";
  document.documentElement.append(element);
  tooltip = element;
  return element;
}

function placeTooltip(event: MouseEvent) {
  const element = ensureTooltip();
  element.style.left = `${Math.min(event.clientX + 14, window.innerWidth - 340)}px`;
  element.style.top = `${Math.min(event.clientY + 18, window.innerHeight - 120)}px`;
}

function hideTooltip() {
  tooltip?.remove();
  tooltip = null;
  activeToken = "";
}

function textHitAtPoint(x: number, y: number): TextHit | null {
  const documentWithRange = document as Document & {
    caretPositionFromPoint?: (x: number, y: number) => { offset: number; offsetNode: Node } | null;
    caretRangeFromPoint?: (x: number, y: number) => Range | null;
  };
  const position = documentWithRange.caretPositionFromPoint?.(x, y);
  if (position?.offsetNode.nodeType === Node.TEXT_NODE) {
    return { node: position.offsetNode as Text, offset: position.offset };
  }

  const range = documentWithRange.caretRangeFromPoint?.(x, y);
  if (range?.startContainer.nodeType === Node.TEXT_NODE) {
    return { node: range.startContainer as Text, offset: range.startOffset };
  }

  return null;
}

function tokenAt(hit: TextHit): string | null {
  const text = hit.node.textContent ?? "";
  for (const match of text.matchAll(/\b[A-Z][A-Z0-9]{1,9}\b/g)) {
    const start = match.index ?? 0;
    const end = start + match[0].length;
    if (hit.offset >= start && hit.offset <= end) return match[0];
  }

  return null;
}

function canHighlightNode(node: Text): boolean {
  const parent = node.parentElement;
  if (!parent || parent.closest("script, style, textarea, input, [contenteditable='true']")) {
    return false;
  }

  return !parent.closest(".wat-acronym-highlight");
}

function installHighlightStyle() {
  if (document.getElementById("wat-highlight-style")) return;

  const style = document.createElement("style");
  style.id = "wat-highlight-style";
  style.textContent =
    ".wat-acronym-highlight{text-decoration:underline dotted #2563eb 2px;text-underline-offset:3px;cursor:help;}";
  document.documentElement.append(style);
}

function highlightTextNode(node: Text): number {
  const text = node.textContent ?? "";
  const matches = [...text.matchAll(/\b[A-Z][A-Z0-9]{1,9}\b/g)];
  if (matches.length === 0) return 0;

  const fragment = document.createDocumentFragment();
  let cursor = 0;
  for (const match of matches) {
    const start = match.index ?? 0;
    const token = match[0];
    fragment.append(document.createTextNode(text.slice(cursor, start)));

    const span = document.createElement("span");
    span.className = "wat-acronym-highlight";
    span.dataset.watToken = token;
    span.textContent = token;
    span.title = token;
    fragment.append(span);
    cursor = start + token.length;
  }
  fragment.append(document.createTextNode(text.slice(cursor)));
  node.replaceWith(fragment);

  return matches.length;
}

function highlightAcronyms(limit = 300) {
  installHighlightStyle();
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      return canHighlightNode(node as Text) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
    }
  });
  const nodes: Text[] = [];
  while (walker.nextNode()) nodes.push(walker.currentNode as Text);

  let count = 0;
  for (const node of nodes) {
    count += highlightTextNode(node);
    if (count >= limit) return;
  }
}

function installHeatmapStyle() {
  if (document.getElementById("wat-heatmap-style")) return;

  const style = document.createElement("style");
  style.id = "wat-heatmap-style";
  style.textContent =
    ".wat-acronym-heatmap{--wat-heatmap-alpha:0.1;background:linear-gradient(90deg,rgb(37 99 235 / var(--wat-heatmap-alpha)),transparent 70%);box-shadow:inset 4px 0 0 rgb(37 99 235);border-radius:4px;}";
  document.documentElement.append(style);
}

function canHeatmapElement(element: Element): element is HTMLElement {
  return (
    element instanceof HTMLElement &&
    !element.closest("script, style, textarea, input, [contenteditable='true']") &&
    !element.closest(".wat-acronym-highlight")
  );
}

function applyAcronymHeatmap(limit = 200) {
  installHeatmapStyle();
  const candidates = Array.from(document.querySelectorAll("p,li,blockquote")).filter(
    canHeatmapElement
  );
  let count = 0;
  for (const element of candidates) {
    const density = acronymDensityForText(element.textContent ?? "");
    if (density.level === 0) continue;
    element.classList.add("wat-acronym-heatmap");
    element.dataset.watAcronymCount = String(density.count);
    element.dataset.watOriginalTitle = element.title;
    element.style.setProperty("--wat-heatmap-alpha", heatmapAlpha(density.level));
    element.title = element.title
      ? `${element.title} - wat acronym count: ${density.count}`
      : `wat acronym count: ${density.count}`;
    heatmapElements.add(element);
    count += 1;
    if (count >= limit) return;
  }
}

function clearAcronymHeatmap() {
  for (const element of heatmapElements) {
    element.classList.remove("wat-acronym-heatmap");
    element.style.removeProperty("--wat-heatmap-alpha");
    element.title = element.dataset.watOriginalTitle ?? "";
    delete element.dataset.watAcronymCount;
    delete element.dataset.watOriginalTitle;
  }
  heatmapElements.clear();
  heatmapInstalled = false;
}

function setHeatmap(enabled: boolean) {
  if (enabled && !heatmapInstalled) {
    applyAcronymHeatmap();
    heatmapInstalled = true;
  }
  if (!enabled && heatmapInstalled) {
    clearAcronymHeatmap();
  }
}

function topEntry(body: unknown): SearchEntry | null {
  const searchBody = body as SearchBody;
  return searchBody.matches?.[0]?.entry ?? null;
}

function renderResult(term: string, response: LookupResponse) {
  const element = ensureTooltip();
  if (!response.ok) {
    element.textContent = `${term}: no result`;
    return;
  }

  const entry = topEntry(response.body);
  if (!entry) {
    element.textContent = `${term}: no result`;
    return;
  }

  const source = entry.sources?.[0];
  element.replaceChildren();
  const title = document.createElement("div");
  title.textContent = `${entry.term ?? term}: ${entry.expansions?.[0] ?? term}`;
  title.style.fontWeight = "700";
  element.append(title);

  if (entry.meaning_short) {
    const meaning = document.createElement("div");
    meaning.textContent = entry.meaning_short;
    meaning.style.color = "#e4e4e7";
    meaning.style.marginTop = "6px";
    element.append(meaning);
  }

  const alternatives = formatAlternativesLine(entry.contemporaries);
  if (alternatives) {
    const alternativesLine = document.createElement("div");
    alternativesLine.textContent = alternatives;
    alternativesLine.style.color = "#d4d4d8";
    alternativesLine.style.marginTop = "6px";
    element.append(alternativesLine);
  }

  if (source?.url) {
    const sourceLine = document.createElement("div");
    sourceLine.textContent = source.title ? `${source.title} - ${source.url}` : source.url;
    sourceLine.style.color = "#d4d4d8";
    sourceLine.style.marginTop = "4px";
    element.append(sourceLine);
  }
}

function pageContext(): string {
  const headings = Array.from(document.querySelectorAll("h1,h2,h3"))
    .map((element) => element.textContent?.trim())
    .filter((text): text is string => Boolean(text))
    .slice(0, 12);

  return [location.hostname, document.title, ...headings].join(" ").slice(0, 1200);
}

function lookup(term: string, event: MouseEvent) {
  placeTooltip(event);
  ensureTooltip().textContent = `${term}: loading`;
  void browser.runtime
    .sendMessage({ context: pageContext(), limit: 1, term, type: "wat.lookup" })
    .then((response: LookupResponse) => {
      if (activeToken === term) renderResult(term, response);
    });
}

function scheduleLookup(event: MouseEvent) {
  const hit = textHitAtPoint(event.clientX, event.clientY);
  const token = hit ? tokenAt(hit) : null;
  if (!token) {
    hideTooltip();
    return;
  }
  if (token === activeToken) {
    placeTooltip(event);
    return;
  }

  activeToken = token;
  window.clearTimeout(hoverTimer);
  hoverTimer = window.setTimeout(() => lookup(token, event), 180);
}

export default defineContentScript({
  matches: ["<all_urls>"],
  async main() {
    applyOptions(await loadLocalWatOptions());
    void loadContentOptions().then(applyOptions);
  }
});
