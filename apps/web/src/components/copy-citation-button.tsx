"use client";

import { Check, Clipboard, X } from "lucide-react";
import { useEffect, useState } from "react";
import type { SearchEntry } from "@wat/search";

import { copyTextToClipboard, formatCitation } from "@/components/copy-citation";
import { Button } from "@/components/ui/button";

interface CopyCitationButtonProps {
  entry: SearchEntry;
}

type CopyState = "idle" | "copied" | "failed";

export function CopyCitationButton({ entry }: CopyCitationButtonProps) {
  const [copyState, setCopyState] = useState<CopyState>("idle");

  useEffect(() => {
    if (copyState === "idle") {
      return;
    }

    const timer = window.setTimeout(() => setCopyState("idle"), 1200);
    return () => window.clearTimeout(timer);
  }, [copyState]);

  async function copyCitation() {
    setCopyState((await copyTextToClipboard(formatCitation(entry))) ? "copied" : "failed");
  }

  const label =
    copyState === "copied"
      ? "Citation copied"
      : copyState === "failed"
        ? "Copy failed"
        : "Copy citation";

  return (
    <Button
      aria-label={label}
      onClick={copyCitation}
      size="icon"
      title={label}
      type="button"
      variant="outline"
    >
      {copyState === "copied" ? <Check /> : copyState === "failed" ? <X /> : <Clipboard />}
    </Button>
  );
}
