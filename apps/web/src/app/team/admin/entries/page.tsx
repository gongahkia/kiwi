import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { TeamEntryCrud } from "@/components/team-entry-crud";
import { sessionUserFromCookieStore } from "@/lib/session";
import { getTeamEntries } from "@/lib/team-entries";

export default async function TeamEntriesPage() {
  const session = await sessionUserFromCookieStore(await cookies());
  if (!session?.teamId) redirect("/login?next=/team/admin/entries");
  const entries = await getTeamEntries(session.teamId);

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-6xl gap-6">
        <header className="grid gap-2">
          <Link
            className="text-sm text-foreground/65 underline-offset-4 hover:underline"
            href="/team/admin"
          >
            Team dashboard
          </Link>
          <h1 className="text-4xl font-semibold">Team entries</h1>
        </header>
        <TeamEntryCrud initialEntries={entries} />
      </div>
    </main>
  );
}
