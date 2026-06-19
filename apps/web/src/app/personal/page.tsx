import { cookies } from "next/headers";
import Link from "next/link";

import { TeamEntryCrud } from "@/components/team-entry-crud";
import { getPersonalEntries } from "@/lib/personal-entries";

const sessionCookie = "wat_session";

export default async function PersonalPage() {
  const cookieStore = await cookies();
  const userId = cookieStore.get(sessionCookie)?.value ?? "anonymous";

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-6xl gap-6">
        <header className="grid gap-2">
          <h1 className="text-4xl font-semibold">Personal glossary</h1>
          <div className="flex flex-wrap gap-2 text-sm">
            <Link className="rounded-md border border-input px-3 py-2" href="/">
              Search
            </Link>
            <Link className="rounded-md border border-input px-3 py-2" href="/personal/export/json">
              Export JSON
            </Link>
            <Link className="rounded-md border border-input px-3 py-2" href="/personal/export/csv">
              Export CSV
            </Link>
          </div>
        </header>
        <TeamEntryCrud
          apiPath="/personal/api"
          defaultDomains="private"
          initialEntries={getPersonalEntries(userId)}
          layerLabel="personal"
          sourceLabel="personal"
        />
      </div>
    </main>
  );
}
