"use client";

import { Check, Clipboard } from "lucide-react";
import { useEffect, useState } from "react";
import type { SearchEntry } from "@wat/search";

import { copyTextToClipboard, formatCitation } from "@/components/copy-citation";
import { Button } from "@/components/ui/button";

interface CopyCitationButtonProps {
  entry: SearchEntry;
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
    setCopied(await copyTextToClipboard(formatCitation(entry)));
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
