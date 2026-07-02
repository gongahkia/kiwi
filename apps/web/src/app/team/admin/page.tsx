import { Activity, BookOpen, CheckCircle2, Circle, Users } from "lucide-react";
import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { sessionUserFromCookieStore } from "@/lib/session";
import { teamAdminChecklist, type TeamAdminChecklistItem } from "@/lib/team-admin-checklist";
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

function AnalyticsMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="grid gap-1 rounded-md border border-input p-3">
      <p className="text-xs text-foreground/55">{label}</p>
      <p className="text-2xl font-semibold tabular-nums">{value}</p>
    </div>
  );
}

function formatRate(value: number): string {
  return `${Math.round(value * 100)}%`;
}

function AnalyticsList({ items }: { items: Record<string, number> }) {
  const entries = Object.entries(items).sort(([left], [right]) => left.localeCompare(right));
  if (entries.length === 0) return <p className="text-sm text-foreground/55">None</p>;

  return (
    <ul className="grid gap-2">
      {entries.map(([label, value]) => (
        <li className="flex items-center justify-between gap-3 text-sm" key={label}>
          <span>{label}</span>
          <span className="tabular-nums text-foreground/65">{value}</span>
        </li>
      ))}
    </ul>
  );
}

function ChecklistItem({ item }: { item: TeamAdminChecklistItem }) {
  const Icon = item.complete ? CheckCircle2 : Circle;

  return (
    <li className="flex items-center justify-between gap-3 border-t border-input py-3 first:border-t-0">
      <div className="flex items-center gap-3">
        <Icon className="size-4 text-foreground/55" />
        <div className="grid gap-1">
          <p className="text-sm">{item.label}</p>
          <p className="text-xs text-foreground/55">{item.complete ? "Done" : "Pending"}</p>
        </div>
      </div>
      <Link className="text-sm underline underline-offset-4" href={item.href}>
        {item.nextAction}
      </Link>
    </li>
  );
}

export default async function TeamAdminPage() {
  const session = await sessionUserFromCookieStore(await cookies());
  if (!session?.teamId) redirect("/login?next=/team/admin");
  const dashboard = await getTeamDashboardSnapshot(session.teamId);
  const checklist = teamAdminChecklist({
    memberCount: dashboard.memberCount,
    teamEntryCount: dashboard.counts.team
  });

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
            <Link className="rounded-md border border-input px-3 py-2" href="/team/admin/api-keys">
              API keys
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
        <section className="grid gap-4 rounded-md border border-input p-4">
          <h2 className="text-xl font-semibold">Search analytics</h2>
          <div className="grid gap-3 sm:grid-cols-3">
            <AnalyticsMetric label="Searches" value={String(dashboard.searchAnalytics.total)} />
            <AnalyticsMetric
              label="No-result rate"
              value={formatRate(dashboard.searchAnalytics.noResultRate)}
            />
            <AnalyticsMetric
              label="p95 latency"
              value={`${dashboard.searchAnalytics.p95LatencyMs} ms`}
            />
          </div>
          <div className="grid gap-4 md:grid-cols-3">
            <div className="grid gap-2">
              <h3 className="text-sm font-medium">Layer hits</h3>
              <AnalyticsList items={dashboard.searchAnalytics.layerHits} />
            </div>
            <div className="grid gap-2">
              <h3 className="text-sm font-medium">Confidence</h3>
              <AnalyticsList items={dashboard.searchAnalytics.confidenceDistribution} />
            </div>
            <div className="grid gap-2">
              <h3 className="text-sm font-medium">Recent hashes</h3>
              {dashboard.searchAnalytics.recentQueryHashes.length > 0 ? (
                <ul className="grid gap-2">
                  {dashboard.searchAnalytics.recentQueryHashes.map((hash) => (
                    <li className="truncate font-mono text-xs text-foreground/65" key={hash}>
                      {hash}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-sm text-foreground/55">None</p>
              )}
            </div>
          </div>
        </section>
        <section className="grid gap-3 rounded-md border border-input p-4">
          <h2 className="text-xl font-semibold">Admin checklist</h2>
          <ul>
            {checklist.map((item) => (
              <ChecklistItem item={item} key={item.label} />
            ))}
          </ul>
        </section>
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
