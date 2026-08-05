import { Suspense } from "react";

import { SearchData } from "@/components/search-data";
import { SearchShell } from "@/components/search-shell";
import { ThemeToggle } from "@/components/theme-toggle";

interface HomeProps {
  searchParams?: Promise<{
    min_confidence?: string;
    q?: string;
  }>;
}

export default async function Home({ searchParams }: HomeProps) {
  const params = await searchParams;
  const query = params?.q ?? "";
  const includeLowConfidence = params?.min_confidence === "T4";

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="absolute right-4 top-4">
        <ThemeToggle />
      </div>
      <Suspense
        fallback={
          <SearchShell
            entries={[]}
            initialIncludeLowConfidence={includeLowConfidence}
            initialQuery={query}
            isLoading
          />
        }
      >
        <SearchData includeLowConfidence={includeLowConfidence} query={query} />
      </Suspense>
    </main>
  );
}
