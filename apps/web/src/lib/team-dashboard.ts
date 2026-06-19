import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { getTeamEntries } from "@/lib/team-entries";

interface PublicEntry {
  layer: string;
}

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

async function readSeedJson(): Promise<string> {
  for (const seedPath of [
    join(process.cwd(), "packages/ingest/seeds/manual.json"),
    join(process.cwd(), "../../packages/ingest/seeds/manual.json")
  ]) {
    try {
      return await readFile(seedPath, "utf8");
    } catch {
      continue;
    }
  }

  throw new Error("manual seed file not found");
}

export async function getTeamDashboardSnapshot(): Promise<TeamDashboardSnapshot> {
  const parsed = JSON.parse(await readSeedJson()) as { entries: PublicEntry[] };
  const publicCount = parsed.entries.filter((entry) => entry.layer === "public").length;
  const teamEntries = getTeamEntries();

  return {
    counts: {
      personal: 0,
      public: publicCount,
      team: teamEntries.length
    },
    memberCount: 3,
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
