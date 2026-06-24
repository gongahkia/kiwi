import { Activity, BookOpen, Users } from "lucide-react";
import Link from "next/link";

import { getTeamDashboardSnapshot } from "@/lib/team-dashboard";

function Stat({
  label,
  value,
  icon: Icon
}: {
  icon: typeof BookOpen;
  label: string;
  value: number;
}) {
  return (
    <section className="grid gap-2 rounded-md border border-input p-4">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-foreground/65">{label}</p>
        <Icon className="size-4 text-foreground/50" />
      </div>
      <p className="text-3xl font-semibold tabular-nums">{value}</p>
    </section>
  );
}

export default async function TeamAdminPage() {
  const dashboard = await getTeamDashboardSnapshot();

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-5xl gap-8">
        <header className="grid gap-2">
          <p className="text-sm font-medium uppercase tracking-normal text-foreground/55">
            {dashboard.teamName}
          </p>
          <h1 className="text-4xl font-semibold">Team dashboard</h1>
          <div className="flex flex-wrap gap-2 text-sm">
            <Link
              className="rounded-md border border-input px-3 py-2"
              href="/team/admin/export/json"
            >
              Export JSON
            </Link>
            <Link
              className="rounded-md border border-input px-3 py-2"
              href="/team/admin/export/csv"
            >
              Export CSV
            </Link>
            <Link className="rounded-md border border-input px-3 py-2" href="/team/admin/import">
              Import
            </Link>
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
            <Link className="rounded-md border border-input px-3 py-2" href="/team/admin/settings">
              Settings
            </Link>
            <Link className="rounded-md border border-input px-3 py-2" href="/team/admin/members">
              Members
            </Link>
            <Link className="rounded-md border border-input px-3 py-2" href="/team/admin/entries">
              Entries
            </Link>
            <Link className="rounded-md border border-input px-3 py-2" href="/team/admin/review">
              Review
            </Link>
          </div>
        </header>
        <div className="grid gap-4 md:grid-cols-4">
          <Stat icon={BookOpen} label="Team entries" value={dashboard.counts.team} />
          <Stat icon={BookOpen} label="Public entries" value={dashboard.counts.public} />
          <Stat icon={BookOpen} label="Personal entries" value={dashboard.counts.personal} />
          <Stat icon={Users} label="Members" value={dashboard.memberCount} />
        </div>
        <section className="grid gap-3">
          <div className="flex items-center gap-2">
            <Activity className="size-5 text-foreground/60" />
            <h2 className="text-xl font-semibold">Recent activity</h2>
          </div>
          <div className="overflow-x-auto rounded-md border border-input">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-secondary">
                <tr>
                  <th className="px-3 py-2 font-medium">Time</th>
                  <th className="px-3 py-2 font-medium">Actor</th>
                  <th className="px-3 py-2 font-medium">Event</th>
                </tr>
              </thead>
              <tbody>
                {dashboard.recentActivity.map((item) => (
                  <tr className="border-t border-input" key={`${item.time}-${item.event}`}>
                    <td className="px-3 py-2 tabular-nums text-foreground/70">{item.time}</td>
                    <td className="px-3 py-2">{item.actor}</td>
                    <td className="px-3 py-2">{item.event}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </main>
  );
}
