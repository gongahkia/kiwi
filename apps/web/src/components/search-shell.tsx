"use client";

import { Loader2, Search } from "lucide-react";
import { type FormEvent, type KeyboardEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { SearchResponse, SearchResult } from "@wat/search";

import { DomainTeaser } from "@/components/domain-teaser";
import { SearchResultCard } from "@/components/search-result-card";
import { Button } from "@/components/ui/button";

type SearchStatus = "idle" | "loading" | "ready" | "error";

interface SearchShellProps {
  initialQuery?: string;
}

export function SearchShell({ initialQuery = "" }: SearchShellProps) {
  const router = useRouter();
  const [query, setQuery] = useState(initialQuery);
  const [debouncedQuery, setDebouncedQuery] = useState(initialQuery.trim());
  const [includeLowConfidence, setIncludeLowConfidence] = useState(false);
  const [matches, setMatches] = useState<SearchResult[]>([]);
  const [domain, setDomain] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(-1);
  const [status, setStatus] = useState<SearchStatus>(initialQuery.trim() ? "loading" : "idle");

  const domainOptions = useMemo(
    () => Array.from(new Set(matches.flatMap((match) => match.entry.domains))).sort(),
    [matches]
  );
  const visibleMatches = useMemo(
    () => (domain ? matches.filter((match) => match.entry.domains.includes(domain)) : matches),
    [domain, matches]
  );

  useEffect(() => {
    const timer = window.setTimeout(() => setDebouncedQuery(query.trim()), 180);
    return () => window.clearTimeout(timer);
  }, [query]);

  useEffect(() => {
    if (!debouncedQuery) {
      setMatches([]);
      setDomain("");
      setStatus("idle");
      return;
    }

    const controller = new AbortController();
    setStatus("loading");

    const confidenceParam = includeLowConfidence ? "" : "&min_confidence=T2";
    void fetch(`/api/v1/search?q=${encodeURIComponent(debouncedQuery)}&limit=8${confidenceParam}`, {
      signal: controller.signal
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error("search failed");
        }
        return response.json() as Promise<SearchResponse>;
      })
      .then((body) => {
        setMatches(body.matches);
        setStatus("ready");
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") {
          return;
        }
        setMatches([]);
        setStatus("error");
      });

    return () => controller.abort();
  }, [debouncedQuery, includeLowConfidence]);

  useEffect(() => {
    if (domain && !domainOptions.includes(domain)) {
      setDomain("");
    }
  }, [domain, domainOptions]);

  useEffect(() => {
    setSelectedIndex(-1);
  }, [debouncedQuery, domain]);

  useEffect(() => {
    if (selectedIndex >= visibleMatches.length) {
      setSelectedIndex(-1);
    }
  }, [selectedIndex, visibleMatches.length]);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setDebouncedQuery(query.trim());
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

    if (event.key === "Enter" && selectedIndex >= 0) {
      event.preventDefault();
      router.push(`/term/${visibleMatches[selectedIndex]!.entry.id}`);
    }
  }

  return (
    <section className="grid w-full max-w-[760px] gap-6">
      <form className="grid gap-4" onSubmit={handleSubmit}>
        <h1 className="text-[56px] font-bold leading-none">wat</h1>
        <div className="flex gap-2">
          <input
            aria-label="Search"
            autoFocus
            className="h-11 min-w-0 flex-1 rounded-md border border-input bg-background px-4 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring"
            name="q"
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={handleSearchKeyDown}
            placeholder="API, CAP, TLS"
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
        {status === "error" ? <p className="text-sm text-foreground/60">Search failed.</p> : null}
        {status === "ready" && visibleMatches.length === 0 ? (
          <p className="text-sm text-foreground/60">No results.</p>
        ) : null}
        {visibleMatches.map((result, index) => (
          <SearchResultCard
            className={
              selectedIndex === index ? "border-ring bg-accent/40 ring-2 ring-ring" : undefined
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
