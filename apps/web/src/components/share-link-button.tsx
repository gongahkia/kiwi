"use client";

import { Check, LinkIcon, X } from "lucide-react";
import { useEffect, useState } from "react";

import { copyTextToClipboard } from "@/components/copy-citation";
import { Button } from "@/components/ui/button";

interface ShareLinkButtonProps {
  path: string;
}

type CopyState = "idle" | "copied" | "failed";

export function ShareLinkButton({ path }: ShareLinkButtonProps) {
  const [copyState, setCopyState] = useState<CopyState>("idle");

  useEffect(() => {
    if (copyState === "idle") {
      return;
    }

    const timer = window.setTimeout(() => setCopyState("idle"), 1200);
    return () => window.clearTimeout(timer);
  }, [copyState]);

  async function copyShareLink() {
    setCopyState(
      (await copyTextToClipboard(new URL(path, window.location.origin).toString()))
        ? "copied"
        : "failed"
    );
  }

  const label =
    copyState === "copied"
      ? "Share link copied"
      : copyState === "failed"
        ? "Copy failed"
        : "Copy share link";

  return (
    <Button
      aria-label={label}
      onClick={copyShareLink}
      size="icon"
      title={label}
      type="button"
      variant="outline"
    >
      {copyState === "copied" ? <Check /> : copyState === "failed" ? <X /> : <LinkIcon />}
    </Button>
  );
}
