"use client";

import { Check, Clipboard } from "lucide-react";
import { useEffect, useState } from "react";
import type { SearchEntry } from "@wat/search";

import { Button } from "@/components/ui/button";

interface CopyCitationButtonProps {
  entry: SearchEntry;
}

function formatCitation(entry: SearchEntry) {
  const source = entry.sources[0];
  const expansion = entry.expansions[0] ?? entry.term;

  if (!source) {
    return `**${entry.term}** — ${expansion}`;
  }

  return `**${entry.term}** — ${expansion}. [${source.title}](${source.url}) (${source.publisher}, ${source.license}).`;
}

export function CopyCitationButton({ entry }: CopyCitationButtonProps) {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) {
      return;
    }

    const timer = window.setTimeout(() => setCopied(false), 1200);
    return () => window.clearTimeout(timer);
  }, [copied]);

  async function copyCitation() {
    await navigator.clipboard.writeText(formatCitation(entry));
    setCopied(true);
  }

  return (
    <Button
      aria-label={copied ? "Citation copied" : "Copy citation"}
      onClick={copyCitation}
      size="icon"
      title={copied ? "Citation copied" : "Copy citation"}
      type="button"
      variant="outline"
    >
      {copied ? <Check /> : <Clipboard />}
    </Button>
  );
}
