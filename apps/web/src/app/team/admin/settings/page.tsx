import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { sessionUserFromCookieStore } from "@/lib/session";
import { getTeamSettings } from "@/lib/team-settings";

export default async function TeamSettingsPage() {
  const session = await sessionUserFromCookieStore(await cookies());
  if (!session?.teamId) redirect("/login?next=/team/admin/settings");
  const settings = await getTeamSettings(session.teamId);

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
        <section className="grid gap-3 rounded-md border border-input p-4">
          <dl className="grid gap-3 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="text-foreground/65">Default domain filter</dt>
              <dd>{settings.default_domain_filter}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-foreground/65">Allow public layer</dt>
              <dd>{settings.allow_public_layer ? "enabled" : "disabled"}</dd>
            </div>
          </dl>
        </section>
        <section className="grid gap-3">
          <h2 className="text-xl font-semibold">Domain tags</h2>
          <div className="flex flex-wrap gap-2">
            {settings.domain_tags.map((tag) => (
              <span className="rounded-md border border-input px-3 py-2 text-sm" key={tag}>
                {tag}
              </span>
            ))}
          </div>
        </section>
      </div>
    </main>
  );
}
