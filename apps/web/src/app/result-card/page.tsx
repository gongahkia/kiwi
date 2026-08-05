import type { SearchEntry } from "@wat/search";

import { SearchResultCard } from "@/components/search-result-card";
import { getPublicCorpusEntries } from "@/lib/public-corpus";

async function getSampleEntry(): Promise<SearchEntry> {
  const entries = await getPublicCorpusEntries();
  return entries.find((entry) => entry.id === "seed-api-application-programming-interface")!;
}

export default async function ResultCardPage() {
  const entry = await getSampleEntry();

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <section className="mx-auto grid max-w-2xl gap-4">
        <h1 className="text-3xl font-semibold">Result card</h1>
        <SearchResultCard entry={entry} />
      </section>
    </main>
  );
}
