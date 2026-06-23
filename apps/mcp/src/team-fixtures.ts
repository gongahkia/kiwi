import type { WatEntry } from "./types.js";

export const devTeamEntries: WatEntry[] = [
  {
    aliases: ["change review"],
    confidence_tier: "T2",
    contemporaries: [],
    domains: ["example.com", "platform"],
    expansions: ["Change Approval Process"],
    id: "team-example-cap",
    layer: "team",
    meaning_short: "Internal release-gating process for production-impacting changes.",
    sources: [
      {
        license: "MIT",
        publisher: "wat dev fixture",
        retrieved_at: "2026-06-19T00:00:00.000Z",
        snippet: "CAP is the release-gating review for production-impacting changes.",
        source_quality: "canonical",
        title: "example.com team glossary fixture",
        url: "https://example.com/glossary/cap"
      }
    ],
    team_id: "team_example",
    term: "CAP",
    term_normalized: "cap"
  },
  {
    aliases: ["deploy lock"],
    confidence_tier: "T2",
    contemporaries: [],
    domains: ["example.com", "ops"],
    expansions: ["Deployment Freeze"],
    id: "team-example-df",
    layer: "team",
    meaning_short:
      "Internal freeze window where production deploys require incident-lead approval.",
    sources: [
      {
        license: "MIT",
        publisher: "wat dev fixture",
        retrieved_at: "2026-06-19T00:00:00.000Z",
        snippet: "DF marks a deploy freeze window for production systems.",
        source_quality: "canonical",
        title: "example.com deployment glossary fixture",
        url: "https://example.com/glossary/df"
      }
    ],
    team_id: "team_example",
    term: "DF",
    term_normalized: "df"
  }
];
