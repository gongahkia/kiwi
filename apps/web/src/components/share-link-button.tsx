"use client";

import { Check, LinkIcon } from "lucide-react";
import { useEffect, useState } from "react";

import { Button } from "@/components/ui/button";

interface ShareLinkButtonProps {
  path: string;
}

export function ShareLinkButton({ path }: ShareLinkButtonProps) {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) {
      return;
    }

    const timer = window.setTimeout(() => setCopied(false), 1200);
    return () => window.clearTimeout(timer);
  }, [copied]);

  async function copyShareLink() {
    await navigator.clipboard.writeText(new URL(path, window.location.origin).toString());
    setCopied(true);
  }

  return (
    <Button
      aria-label={copied ? "Share link copied" : "Copy share link"}
      onClick={copyShareLink}
      size="icon"
      title={copied ? "Share link copied" : "Copy share link"}
      type="button"
      variant="outline"
    >
      {copied ? <Check /> : <LinkIcon />}
    </Button>
  );
}
