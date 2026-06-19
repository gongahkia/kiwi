export interface TeamEntrySource {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet: string;
  title: string;
  url: string;
}

export interface TeamEntry {
  domains: string[];
  expansion: string;
  id: string;
  meaning: string;
  sources: TeamEntrySource[];
  term: string;
}

export const teamEntries: TeamEntry[] = [
  {
    domains: ["example.com", "platform"],
    expansion: "Change Approval Process",
    id: "team-example-cap",
    meaning: "Internal release-gating process for production-impacting changes.",
    sources: [
      {
        license: "MIT",
        publisher: "wat dev fixture",
        retrieved_at: "2026-06-19T00:00:00.000Z",
        snippet: "CAP is the release-gating review for production-impacting changes.",
        title: "example.com team glossary fixture",
        url: "https://example.com/glossary/cap"
      }
    ],
    term: "CAP"
  },
  {
    domains: ["example.com", "ops"],
    expansion: "Deployment Freeze",
    id: "team-example-df",
    meaning: "Internal freeze window where production deploys require incident-lead approval.",
    sources: [
      {
        license: "MIT",
        publisher: "wat dev fixture",
        retrieved_at: "2026-06-19T00:00:00.000Z",
        snippet: "DF marks a deploy freeze window for production systems.",
        title: "example.com deployment glossary fixture",
        url: "https://example.com/glossary/df"
      }
    ],
    term: "DF"
  }
];

function csvCell(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

export function teamEntriesCsv(entries = teamEntries): string {
  const header = ["id", "term", "expansion", "meaning", "domains", "sources"];
  const rows = entries.map((entry) =>
    [
      entry.id,
      entry.term,
      entry.expansion,
      entry.meaning,
      entry.domains.join(";"),
      entry.sources.map((source) => source.url).join(";")
    ]
      .map(csvCell)
      .join(",")
  );

  return `${header.join(",")}\n${rows.join("\n")}\n`;
}
