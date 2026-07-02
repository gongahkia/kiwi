import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { AdminEmptyState } from "@/components/admin-empty-state";
import { TeamMembersPanel } from "@/components/team-members-panel";
import { adminEmptyStates } from "@/lib/admin-empty-states";
import { sessionUserFromCookieStore } from "@/lib/session";
import { listTeamInvites } from "@/lib/team-invites";
import { getTeamMembers } from "@/lib/team-members";

export default async function TeamMembersPage() {
  const session = await sessionUserFromCookieStore(await cookies());
  if (!session?.teamId) redirect("/login?next=/team/admin/members");
  const [members, invites] = await Promise.all([
    getTeamMembers(session.teamId),
    listTeamInvites(session.teamId)
  ]);

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-4xl gap-6">
        <header className="grid gap-2">
          <Link
            className="text-sm text-foreground/65 underline-offset-4 hover:underline"
            href="/team/admin"
          >
            Team dashboard
          </Link>
          <h1 className="text-4xl font-semibold">Team members</h1>
        </header>
        {members.length === 0 && invites.length === 0 ? (
          <AdminEmptyState {...adminEmptyStates.members} />
        ) : (
          <TeamMembersPanel initialInvites={invites} initialMembers={members} />
        )}
      </div>
    </main>
  );
}
