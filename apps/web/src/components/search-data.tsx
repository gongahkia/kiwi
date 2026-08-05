import { SearchShell } from "@/components/search-shell";
import { getVisibleEntriesForSession } from "@/lib/search-data";
import { sessionUserFromCookieStore } from "@/lib/session";
import { cookies } from "next/headers";

interface SearchDataProps {
  includeLowConfidence: boolean;
  query: string;
}

export async function SearchData({ includeLowConfidence, query }: SearchDataProps) {
  const session = await sessionUserFromCookieStore(await cookies());
  const entries = await getVisibleEntriesForSession(session);

  return (
    <SearchShell
      entries={entries}
      initialIncludeLowConfidence={includeLowConfidence}
      initialQuery={query}
    />
  );
}
