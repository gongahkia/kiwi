import { SearchShell } from "@/components/search-shell";
import { ThemeToggle } from "@/components/theme-toggle";

interface HomeProps {
  searchParams?: Promise<{
    q?: string;
  }>;
}

export default async function Home({ searchParams }: HomeProps) {
  const params = await searchParams;

  return (
    <main className="grid min-h-svh place-items-center bg-background p-6 text-foreground">
      <div className="absolute right-4 top-4">
        <ThemeToggle />
      </div>
      <SearchShell initialQuery={params?.q ?? ""} />
    </main>
  );
}
