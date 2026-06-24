import { getPublicCorpusEntries } from "@/lib/public-corpus";
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
  memberCount: number;
  recentActivity: TeamActivity[];
  teamName: string;
}

export async function getTeamDashboardSnapshot(): Promise<TeamDashboardSnapshot> {
  const publicCount = (await getPublicCorpusEntries()).length;
  const teamEntries = getTeamEntries();
  const members = getTeamMembers();

  return {
    counts: {
      personal: 0,
      public: publicCount,
      team: teamEntries.length
    },
    memberCount: members.length,
    recentActivity: [
      {
        actor: "Admin",
        event: "Reviewed CAP suggestion",
        time: "2026-06-19"
      },
      {
        actor: "Platform",
        event: "Imported team glossary fixture",
        time: "2026-06-19"
      },
      {
        actor: "wat",
        event: "Refreshed public corpus baseline",
        time: "2026-06-19"
      }
    ],
    teamName: "example.com"
  };
}
