"use client";

import { Loader2, Search } from "lucide-react";
import { type FormEvent, useEffect, useMemo, useState } from "react";
import type { SearchResponse, SearchResult } from "@wat/search";

import { SearchResultCard } from "@/components/search-result-card";
import { Button } from "@/components/ui/button";

type SearchStatus = "idle" | "loading" | "ready" | "error";

interface SearchShellProps {
  initialQuery?: string;
}

export function SearchShell({ initialQuery = "" }: SearchShellProps) {
  const [query, setQuery] = useState(initialQuery);
  const [debouncedQuery, setDebouncedQuery] = useState(initialQuery.trim());
  const [matches, setMatches] = useState<SearchResult[]>([]);
  const [domain, setDomain] = useState("");
  const [status, setStatus] = useState<SearchStatus>(initialQuery.trim() ? "loading" : "idle");

  const domainOptions = useMemo(
    () => Array.from(new Set(matches.flatMap((match) => match.entry.domains))).sort(),
    [matches]
  );
  const visibleMatches = useMemo(
    () =>
      domain ? matches.filter((match) => match.entry.domains.includes(domain)) : matches,
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

    void fetch(`/api/v1/search?q=${encodeURIComponent(debouncedQuery)}&limit=8`, {
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
  }, [debouncedQuery]);

  useEffect(() => {
    if (domain && !domainOptions.includes(domain)) {
      setDomain("");
    }
  }, [domain, domainOptions]);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setDebouncedQuery(query.trim());
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
        {status === "error" ? (
          <p className="text-sm text-foreground/60">Search failed.</p>
        ) : null}
        {status === "ready" && visibleMatches.length === 0 ? (
          <p className="text-sm text-foreground/60">No results.</p>
        ) : null}
        {visibleMatches.map((result) => (
          <SearchResultCard entry={result.entry} key={result.entry.id} />
        ))}
      </div>
    </section>
  );
}
