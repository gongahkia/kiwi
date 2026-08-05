import Link from "next/link";
import { Search } from "lucide-react";

import { Button } from "@/components/ui/button";

export default function NotFound() {
  return (
    <main className="grid min-h-svh place-items-center bg-background p-6 text-foreground">
      <section className="grid w-full max-w-lg gap-5">
        <div className="grid gap-2">
          <p className="text-sm font-medium text-foreground/60">404</p>
          <h1 className="text-3xl font-semibold">Term not found</h1>
        </div>
        <form action="/" className="flex gap-2">
          <input
            aria-label="Search"
            className="h-11 min-w-0 flex-1 rounded-md border border-input bg-background px-4 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring"
            name="q"
            placeholder="Search another acronym"
            type="search"
          />
          <Button aria-label="Search" size="icon" type="submit">
            <Search />
          </Button>
        </form>
        <Button asChild variant="outline">
          <Link href="/">Back to search</Link>
        </Button>
      </section>
    </main>
  );
}
