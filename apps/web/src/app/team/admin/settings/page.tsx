import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { TeamSettingsPanel } from "@/components/team-settings-panel";
import { sessionUserFromCookieStore } from "@/lib/session";
import { getTeamProfile } from "@/lib/team-profile";
import { getTeamSettings } from "@/lib/team-settings";

export default async function TeamSettingsPage() {
  const session = await sessionUserFromCookieStore(await cookies());
  if (!session?.teamId) redirect("/login?next=/team/admin/settings");
  const [profile, settings] = await Promise.all([
    getTeamProfile(session.teamId),
    getTeamSettings(session.teamId)
  ]);

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-3xl gap-6">
        <header className="grid gap-2">
          <Link
            className="text-sm text-foreground/65 underline-offset-4 hover:underline"
            href="/team/admin"
          >
            Team dashboard
          </Link>
          <h1 className="text-4xl font-semibold">Team settings</h1>
        </header>
        <TeamSettingsPanel initialProfile={profile} initialSettings={settings} />
      </div>
    </main>
  );
}
