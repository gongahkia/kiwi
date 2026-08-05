import { Search } from "lucide-react";

import { Button } from "@/components/ui/button";
import { ThemeToggle } from "@/components/theme-toggle";

export default function ButtonPage() {
  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="absolute right-4 top-4">
        <ThemeToggle />
      </div>
      <div className="flex max-w-3xl flex-wrap items-center gap-3">
        <Button>
          <Search />
          Search
        </Button>
        <Button variant="secondary">Secondary</Button>
        <Button variant="outline">Outline</Button>
      </div>
    </main>
  );
}
