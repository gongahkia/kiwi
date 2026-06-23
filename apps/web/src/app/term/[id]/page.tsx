import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { notFound } from "next/navigation";

import { ShareLinkButton } from "@/components/share-link-button";
import { SuggestEditForm } from "@/components/suggest-edit-form";
import { resolveContemporaryTerms } from "@/lib/contemporaries";

interface TermPageProps {
  params: Promise<{ id: string }>;
}

interface PublicEntry {
  aliases: string[];
  contemporaries: string[];
  created_at: string;
  domains: string[];
  examples: string[];
  expansions: string[];
  id: string;
  layer: string;
  meaning_short: string;
  meaning_long: string;
  sources: {
    license: string;
    publisher: string;
    source_quality: string;
    title: string;
    url: string;
  }[];
  term: string;
  term_normalized: string;
  updated_at: string;
}

async function getEntries(): Promise<PublicEntry[]> {
  const seedJson = await readSeedJson();
  const parsed = JSON.parse(seedJson) as { entries: PublicEntry[] };
  return parsed.entries.filter((entry) => entry.layer === "public");
}

async function readSeedJson(): Promise<string> {
  for (const seedPath of [
    join(process.cwd(), "packages/ingest/seeds/manual.json"),
    join(process.cwd(), "../../packages/ingest/seeds/manual.json")
  ]) {
    try {
      return await readFile(seedPath, "utf8");
    } catch {
      continue;
    }
  }

  throw new Error("manual seed file not found");
}

export async function generateStaticParams() {
  const entries = await getEntries();
  return entries.map((entry) => ({ id: entry.id }));
}

export default async function TermPage({ params }: TermPageProps) {
  const { id } = await params;
  const entries = await getEntries();
  const entry = entries.find((candidate) => candidate.id === id);

  if (!entry) {
    notFound();
  }
  const alternatives = resolveContemporaryTerms(entry.contemporaries, entries);

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <article className="mx-auto grid max-w-3xl gap-8">
        <header className="grid gap-3">
          <div className="flex items-start justify-between gap-3">
            <div className="flex flex-wrap gap-2">
              {entry.domains.map((domain) => (
                <span className="rounded-md bg-secondary px-2 py-1 text-xs" key={domain}>
                  {domain}
                </span>
              ))}
            </div>
            <ShareLinkButton path={`/term/${entry.id}`} />
          </div>
          <h1 className="text-4xl font-semibold">{entry.term}</h1>
          <p className="text-xl text-foreground/75">{entry.expansions.join(" / ")}</p>
          <p className="text-base leading-7">{entry.meaning_long}</p>
        </header>

        {alternatives.length > 0 ? (
          <section className="grid gap-3">
            <h2 className="text-lg font-semibold">Alternatives</h2>
            <div className="flex flex-wrap gap-2">
              {alternatives.map((alternative) =>
                alternative.id ? (
                  <a
                    className="rounded-md border border-input px-2 py-1 text-sm underline-offset-4 hover:underline"
                    href={`/term/${alternative.id}`}
                    key={alternative.term}
                  >
                    {alternative.term}
                  </a>
                ) : (
                  <span
                    className="rounded-md border border-input px-2 py-1 text-sm"
                    key={alternative.term}
                  >
                    {alternative.term}
                  </span>
                )
              )}
            </div>
          </section>
        ) : null}

        <section className="grid gap-3">
          <h2 className="text-lg font-semibold">Examples</h2>
          <ul className="grid gap-2">
            {entry.examples.map((example) => (
              <li className="rounded-md border border-input p-3" key={example}>
                {example}
              </li>
            ))}
          </ul>
        </section>

        <section className="grid gap-3">
          <h2 className="text-lg font-semibold">Sources</h2>
          <ul className="grid gap-3">
            {entry.sources.map((source) => (
              <li className="grid gap-1" key={source.url}>
                <a className="font-medium underline underline-offset-4" href={source.url}>
                  {source.title}
                </a>
                <p className="text-sm text-foreground/70">
                  {source.publisher} · {source.license} · {source.source_quality}
                </p>
              </li>
            ))}
          </ul>
        </section>

        <section className="grid gap-2">
          <h2 className="text-lg font-semibold">History</h2>
          <p className="text-sm text-foreground/70">Created {entry.created_at}</p>
          <p className="text-sm text-foreground/70">Updated {entry.updated_at}</p>
        </section>

        <SuggestEditForm
          entryId={entry.id}
          initialExpansion={entry.expansions[0] ?? ""}
          initialMeaning={entry.meaning_long}
          initialSourceUrl={entry.sources[0]?.url ?? ""}
        />
      </article>
    </main>
  );
}
