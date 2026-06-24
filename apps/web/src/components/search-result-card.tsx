import Link from "next/link";
import type { SearchEntry } from "@wat/search";

import { CopyCitationButton } from "@/components/copy-citation-button";
import { formatAlternativesPreview } from "@/lib/alternatives-preview";
import { confidenceLabel, layerLabel, sourceStatusLabel } from "@/lib/search-result-labels";
import { cn } from "@/lib/utils";

interface SearchResultCardProps {
  className?: string;
  entry: SearchEntry;
}

export function SearchResultCard({ className, entry }: SearchResultCardProps) {
  const alternatives = formatAlternativesPreview(entry.contemporaries);
  const confidence = confidenceLabel(entry.confidence_tier);
  const layer = layerLabel(entry.layer);
  const sourceStatus = sourceStatusLabel(entry);

  return (
    <article className={cn("grid gap-3 rounded-md border border-input p-4", className)}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Link
            className="text-2xl font-semibold underline-offset-4 hover:underline"
            href={`/term/${entry.id}`}
          >
            {entry.term}
          </Link>
          <span className="rounded-md border border-input px-2 py-1 text-xs">{layer}</span>
          <span className="rounded-md bg-secondary px-2 py-1 text-xs">
            {confidence} · {entry.confidence_tier}
          </span>
        </div>
        <CopyCitationButton entry={entry} />
      </div>
      <p className="text-lg text-foreground/80">{entry.expansions[0]}</p>
      {alternatives ? (
        <p className="truncate text-sm text-foreground/60" title={entry.contemporaries.join(", ")}>
          {alternatives}
        </p>
      ) : null}
      <div className="flex flex-wrap gap-2">
        {entry.domains.map((domain) => (
          <span className="rounded-md border border-input px-2 py-1 text-xs" key={domain}>
            {domain}
          </span>
        ))}
      </div>
      <p className="text-sm text-foreground/60">{sourceStatus}</p>
    </article>
  );
}
