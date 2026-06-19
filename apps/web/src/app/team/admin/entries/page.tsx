import Link from "next/link";

import { TeamEntryCrud } from "@/components/team-entry-crud";
import { getTeamEntries } from "@/lib/team-entries";

export default function TeamEntriesPage() {
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
        <TeamEntryCrud initialEntries={getTeamEntries()} />
      </div>
    </main>
  );
}
