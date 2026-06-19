import type { SearchEntry } from "@wat/search";

export function formatCitation(entry: SearchEntry) {
  const source = entry.sources[0];
  const expansion = entry.expansions[0] ?? entry.term;

  if (!source) {
    return `**${entry.term}** — ${expansion}`;
  }

  return `**${entry.term}** — ${expansion}. [${source.title}](${source.url}) (${source.publisher}, ${source.license}).`;
}

export async function copyTextToClipboard(text: string): Promise<boolean> {
  if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      return copyTextWithTextarea(text);
    }
  }

  return copyTextWithTextarea(text);
}

function copyTextWithTextarea(text: string): boolean {
  if (typeof document === "undefined" || !document.body) return false;

  let textarea: HTMLTextAreaElement | null = null;
  try {
    textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.dataset.copyFallback = "true";
    textarea.setAttribute("readonly", "");
    textarea.style.left = "-9999px";
    textarea.style.position = "fixed";
    textarea.style.top = "0";
    document.body.append(textarea);
    textarea.focus();
    textarea.select();
    return document.execCommand("copy");
  } catch {
    return false;
  } finally {
    textarea?.remove();
  }
}
