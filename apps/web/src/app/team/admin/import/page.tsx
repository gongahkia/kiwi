import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { TeamImportPanel } from "@/components/team-import-panel";
import { sessionUserFromCookieStore } from "@/lib/session";
import { getTeamEntries } from "@/lib/team-entries";

export default async function TeamImportPage() {
  const session = await sessionUserFromCookieStore(await cookies());
  if (!session?.teamId) redirect("/login?next=/team/admin/import");
  const entries = await getTeamEntries(session.teamId);

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-5xl gap-6">
        <header className="grid gap-2">
          <Link
            className="text-sm text-foreground/65 underline-offset-4 hover:underline"
            href="/team/admin"
          >
            Team dashboard
          </Link>
          <h1 className="text-4xl font-semibold">Import team glossary</h1>
          <div className="flex flex-wrap gap-2 text-sm">
            <Link
              className="rounded-md border border-input px-3 py-2"
              href="/team/admin/import/template/json"
            >
              JSON template
            </Link>
            <Link
              className="rounded-md border border-input px-3 py-2"
              href="/team/admin/import/template/csv"
            >
              CSV template
            </Link>
          </div>
        </header>
        <TeamImportPanel existingEntries={entries} />
      </div>
    </main>
  );
}
