"use client";

import { Loader2, Search } from "lucide-react";
import {
  type FormEvent,
  type KeyboardEvent,
  useEffect,
  useMemo,
  useRef,
  useState,
  useTransition
} from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { SearchEntry } from "@wat/search";

import { DomainTeaser } from "@/components/domain-teaser";
import { SearchResultCard } from "@/components/search-result-card";
import { Button } from "@/components/ui/button";
import { ambiguityChoices } from "@/lib/ambiguity-choices";
import { noResultActions } from "@/lib/no-result-actions";
import { confidenceLabel, layerLabel } from "@/lib/search-result-labels";
import { searchEntries } from "@/lib/search-core";

type SearchStatus = "idle" | "loading" | "ready";

interface SearchShellProps {
  entries: SearchEntry[];
  initialIncludeLowConfidence?: boolean;
  initialQuery?: string;
  isLoading?: boolean;
}

export function SearchShell({
  entries,
  initialIncludeLowConfidence = false,
  initialQuery = "",
  isLoading = false
}: SearchShellProps) {
  const router = useRouter();
  const searchInputRef = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState(initialQuery);
  const [includeLowConfidence, setIncludeLowConfidence] = useState(initialIncludeLowConfidence);
  const [domain, setDomain] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(-1);
  const [isPending, startTransition] = useTransition();
  const matches = useMemo(
    () =>
      searchEntries({
        entries,
        limit: 8,
        minConfidence: includeLowConfidence ? "T4" : "T2",
        query
      }),
    [entries, includeLowConfidence, query]
  );
  const status: SearchStatus = !query.trim()
    ? "idle"
    : isLoading || isPending
      ? "loading"
      : "ready";
  const noResultTerm = query.trim();
  const noResultLinks = useMemo(() => noResultActions(noResultTerm), [noResultTerm]);

  const domainOptions = useMemo(
    () => Array.from(new Set(matches.flatMap((match) => match.entry.domains))).sort(),
    [matches]
  );
  const visibleMatches = useMemo(
    () => (domain ? matches.filter((match) => match.entry.domains.includes(domain)) : matches),
    [domain, matches]
  );
  const choices = useMemo(() => ambiguityChoices(query, visibleMatches), [query, visibleMatches]);

  useEffect(() => {
    setQuery(initialQuery);
  }, [initialQuery]);

  useEffect(() => {
    setIncludeLowConfidence(initialIncludeLowConfidence);
  }, [initialIncludeLowConfidence]);

  useEffect(() => {
    if (!query.trim() && !isLoading) {
      searchInputRef.current?.focus();
    }
  }, [isLoading, query]);

  useEffect(() => {
    if (domain && !domainOptions.includes(domain)) {
      setDomain("");
    }
  }, [domain, domainOptions]);

  useEffect(() => {
    setSelectedIndex(-1);
  }, [domain, query]);

  useEffect(() => {
    if (selectedIndex >= visibleMatches.length) {
      setSelectedIndex(-1);
    }
  }, [selectedIndex, visibleMatches.length]);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    replaceSearchParams(query, includeLowConfidence);
  }

  function handleSearchKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (visibleMatches.length === 0) {
      return;
    }

    if (event.key === "ArrowDown") {
      event.preventDefault();
      setSelectedIndex((current) => (current + 1) % visibleMatches.length);
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      setSelectedIndex((current) => (current <= 0 ? visibleMatches.length - 1 : current - 1));
    }

    if (event.key === "Enter" && visibleMatches.length > 0) {
      event.preventDefault();
      const nextIndex = selectedIndex >= 0 ? selectedIndex : 0;
      router.push(`/term/${visibleMatches[nextIndex]!.entry.id}`);
    }
  }

  function replaceSearchParams(nextQuery: string, nextIncludeLowConfidence: boolean) {
    const params = new URLSearchParams(window.location.search);
    const trimmedQuery = nextQuery.trim();
    if (trimmedQuery) {
      params.set("q", trimmedQuery);
    } else {
      params.delete("q");
    }
    if (nextIncludeLowConfidence) {
      params.set("min_confidence", "T4");
    } else {
      params.delete("min_confidence");
    }

    const search = params.toString();
    const nextPath = search ? `/?${search}` : "/";
    if (`${window.location.pathname}${window.location.search}` === nextPath) return;
    startTransition(() => router.replace(nextPath));
  }

  return (
    <section className="grid w-full max-w-[760px] gap-8">
      <form className="grid gap-4" onSubmit={handleSubmit}>
        <h1 className="text-[56px] font-bold">wat</h1>
        <div className="flex gap-2">
          <input
            aria-label="Search"
            autoFocus
            className="h-11 min-w-0 flex-1 rounded-md border border-input bg-background px-4 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring"
            name="q"
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={handleSearchKeyDown}
            placeholder="API, CAP, TLS"
            ref={searchInputRef}
            type="search"
            value={query}
          />
          <Button aria-label="Search" size="icon" type="submit">
            {status === "loading" ? <Loader2 className="animate-spin" /> : <Search />}
          </Button>
        </div>
      </form>

      <div aria-live="polite" className="grid gap-3">
        {status !== "idle" ? (
          <label className="flex w-fit items-center gap-2 text-sm text-foreground/70">
            <input
              checked={includeLowConfidence}
              className="size-4"
              onChange={(event) => setIncludeLowConfidence(event.target.checked)}
              type="checkbox"
            />
            Show T3/T4
          </label>
        ) : null}
        {domainOptions.length > 1 ? (
          <select
            aria-label="Domain filter"
            className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring sm:w-fit"
            onChange={(event) => setDomain(event.target.value)}
            value={domain}
          >
            <option value="">All domains</option>
            {domainOptions.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        ) : null}
        {status === "ready" && visibleMatches.length === 0 ? (
          <div className="grid gap-3 rounded-md border border-input p-4">
            <p className="text-sm text-foreground/60">No results.</p>
            <div className="flex flex-wrap gap-2">
              {noResultLinks.map((action, index) => (
                <Button
                  asChild
                  key={action.href}
                  size="sm"
                  variant={index === 0 ? "default" : "outline"}
                >
                  <Link href={action.href}>{action.label}</Link>
                </Button>
              ))}
            </div>
          </div>
        ) : null}
        {choices.length > 1 ? (
          <div className="grid gap-3 rounded-md border border-input p-4">
            <p className="text-sm text-foreground/60">Multiple meanings for {choices[0]?.term}.</p>
            <div className="grid gap-2">
              {choices.map((choice) => (
                <Link
                  className="grid gap-1 rounded-md border border-input p-3 underline-offset-4 hover:underline"
                  href={`/term/${choice.entry_id}`}
                  key={choice.entry_id}
                >
                  <span className="text-sm">{choice.expansion}</span>
                  <span className="text-xs text-foreground/55">
                    {choice.domains.join(", ")} · {layerLabel(choice.layer)} ·{" "}
                    {confidenceLabel(choice.confidence_tier)}
                  </span>
                </Link>
              ))}
            </div>
          </div>
        ) : null}
        {visibleMatches.map((result, index) => (
          <SearchResultCard
            className={
              selectedIndex === index ? "border-ring bg-muted-surface ring-2 ring-ring" : undefined
            }
            entry={result.entry}
            key={result.entry.id}
          />
        ))}
      </div>
      <DomainTeaser />
    </section>
  );
}
