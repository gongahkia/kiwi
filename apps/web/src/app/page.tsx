import { Search } from "lucide-react";

import { Button } from "@/components/ui/button";
import { ThemeToggle } from "@/components/theme-toggle";

export default function Home() {
  return (
    <main className="grid min-h-svh place-items-center bg-background p-6 text-foreground">
      <div className="absolute right-4 top-4">
        <ThemeToggle />
      </div>
      <form className="grid w-full max-w-[720px] gap-4">
        <h1 className="text-[56px] font-bold leading-none">wat</h1>
        <div className="flex gap-2">
          <input
            aria-label="Search"
            autoFocus
            className="h-11 min-w-0 flex-1 rounded-md border border-input bg-background px-4 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring"
            name="q"
            placeholder="API, CAP, TLS"
            type="search"
          />
          <Button aria-label="Search" size="icon" type="submit">
            <Search />
          </Button>
        </div>
      </form>
    </main>
  );
}
