import { SearchShell } from "@/components/search-shell";
import { getPublicEntries } from "@/lib/search-data";

interface SearchDataProps {
  includeLowConfidence: boolean;
  query: string;
}

export async function SearchData({ includeLowConfidence, query }: SearchDataProps) {
  const entries = await getPublicEntries();

  return (
    <SearchShell
      entries={entries}
      initialIncludeLowConfidence={includeLowConfidence}
      initialQuery={query}
    />
  );
}
