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
  const activeElement =
    typeof HTMLElement !== "undefined" && document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
  const selection = document.getSelection?.();
  const ranges =
    selection == null
      ? []
      : Array.from({ length: selection.rangeCount }, (_, index) => selection.getRangeAt(index));

  try {
    textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.dataset.copyFallback = "true";
    textarea.setAttribute("readonly", "");
    textarea.style.left = "0";
    textarea.style.opacity = "0";
    textarea.style.pointerEvents = "none";
    textarea.style.position = "fixed";
    textarea.style.top = "0";
    document.body.appendChild(textarea);
    textarea.focus({ preventScroll: true });
    textarea.select();
    textarea.setSelectionRange(0, text.length);
    return document.execCommand?.("copy") ?? false;
  } catch {
    return false;
  } finally {
    textarea?.remove();
    if (selection) {
      selection.removeAllRanges();
      for (const range of ranges) selection.addRange(range);
    }
    activeElement?.focus({ preventScroll: true });
  }
}
