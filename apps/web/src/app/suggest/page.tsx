import Link from "next/link";

import { SuggestEntryForm } from "@/components/suggest-entry-form";

interface SuggestPageProps {
  searchParams: Promise<{ term?: string }>;
}

export default async function SuggestPage({ searchParams }: SuggestPageProps) {
  const { term = "" } = await searchParams;

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-3xl gap-6">
        <header className="grid gap-2">
          <Link className="text-sm text-foreground/65 underline-offset-4 hover:underline" href="/">
            Search
          </Link>
          <h1 className="text-4xl font-semibold">Suggest entry</h1>
        </header>
        <SuggestEntryForm initialTerm={term} />
      </div>
    </main>
  );
}
