import { authDb } from "@/lib/auth-db";
import { listAuditLogPage } from "@/lib/audit-log";
import { getSearchAnalyticsSummary, type SearchAnalyticsSummary } from "@/lib/search-analytics";
import { getPublicEntries } from "@/lib/search-data";
import { getSuggestedEdits } from "@/lib/suggestions";
import { getTeamMembers } from "@/lib/team-members";
import { getTeamEntries } from "@/lib/team-entries";

export interface TeamActivity {
  actor: string;
  event: string;
  time: string;
}

export interface TeamDashboardSnapshot {
  counts: {
    personal: number;
    public: number;
    team: number;
  };
  glossary: {
    noResultGaps: string[];
    pendingSuggestions: number;
    sourceCoverageRate: number;
    staleEntries: number;
    topTerms: Array<{ count: number; term: string }>;
  };
  memberCount: number;
  recentActivity: TeamActivity[];
  searchAnalytics: SearchAnalyticsSummary;
  teamName: string;
}

export async function getTeamDashboardSnapshot(teamId: string): Promise<TeamDashboardSnapshot> {
  const [publicEntries, teamEntries, members, audit, analytics, team, suggestions] =
    await Promise.all([
      getPublicEntries(),
      getTeamEntries(teamId),
      getTeamMembers(teamId),
      listAuditLogPage(teamId, 0, 3),
      getSearchAnalyticsSummary(teamId),
      teamName(teamId),
      getSuggestedEdits(teamId)
    ]);
  const entriesWithSources = teamEntries.filter((entry) => entry.sources.length > 0).length;

  return {
    counts: {
      personal: 0,
      public: publicEntries.length,
      team: teamEntries.length
    },
    glossary: {
      noResultGaps: analytics.recentNoResultHashes,
      pendingSuggestions: suggestions.filter((suggestion) => suggestion.status === "pending")
        .length,
      sourceCoverageRate: teamEntries.length === 0 ? 0 : entriesWithSources / teamEntries.length,
      staleEntries: teamEntries.filter((entry) => (entry.review_status ?? "active") !== "active")
        .length,
      topTerms: analytics.topTerms
    },
    memberCount: members.length,
    recentActivity: audit.audit.map((entry) => ({
      actor: entry.actor_id,
      event: entry.action,
      time: entry.at.slice(0, 10)
    })),
    searchAnalytics: analytics,
    teamName: team
  };
}

async function teamName(teamId: string): Promise<string> {
  if (process.env.NODE_ENV === "test") return "example.com";
  const { rows } = await authDb().query<{ name: string }>("select name from teams where id = $1", [
    teamId
  ]);
  return rows[0]?.name ?? teamId;
}
