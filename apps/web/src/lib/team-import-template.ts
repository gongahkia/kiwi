import type { TeamEntry, TeamEntrySource } from "./team-entry-model";

const importCsvColumns = [
  "id",
  "term",
  "expansion",
  "meaning",
  "domains",
  "source_url",
  "source_title",
  "source_publisher",
  "source_license",
  "source_retrieved_at",
  "source_snippet"
] as const;

type ImportCsvColumn = (typeof importCsvColumns)[number];

export const teamImportTemplateEntry: TeamEntry = {
  domains: ["platform", "runbooks"],
  expansion: "Recovery Time Objective",
  id: "team-template-rto",
  meaning: "Maximum acceptable time to restore a service after an incident.",
  sources: [
    {
      license: "proprietary-team",
      publisher: "example team docs",
      retrieved_at: "2026-06-24T00:00:00.000Z",
      snippet: "RTO means the maximum acceptable restore time for a service.",
      title: "Team glossary template",
      url: "https://docs.example.com/glossary/rto"
    }
  ],
  term: "RTO"
};

function csvCell(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

function csvRow(values: string[]): string {
  return values.map(csvCell).join(",");
}

function csvValue(entry: TeamEntry, source: TeamEntrySource, column: ImportCsvColumn): string {
  switch (column) {
    case "domains":
      return entry.domains.join(";");
    case "expansion":
      return entry.expansion;
    case "id":
      return entry.id;
    case "meaning":
      return entry.meaning;
    case "source_license":
      return source.license;
    case "source_publisher":
      return source.publisher;
    case "source_retrieved_at":
      return source.retrieved_at;
    case "source_snippet":
      return source.snippet;
    case "source_title":
      return source.title;
    case "source_url":
      return source.url;
    case "term":
      return entry.term;
  }
}

function teamImportCsv(entries: TeamEntry[]): string {
  const rows = entries.map((entry) => {
    const source = entry.sources[0];
    if (!source) return null;
    return csvRow(importCsvColumns.map((column) => csvValue(entry, source, column)));
  });

  return `${importCsvColumns.join(",")}\n${rows.filter((row): row is string => row != null).join("\n")}\n`;
}

export function teamImportJsonTemplate(): string {
  return `${JSON.stringify({ entries: [teamImportTemplateEntry] }, null, 2)}\n`;
}

export function teamImportCsvTemplate(): string {
  return teamImportCsv([teamImportTemplateEntry]);
}

function parseCsvRows(input: string): string[][] | null {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;

  for (let index = 0; index < input.length; index += 1) {
    const char = input[index];

    if (quoted) {
      if (char === '"' && input[index + 1] === '"') {
        cell += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        cell += char;
      }
      continue;
    }

    if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(cell);
      cell = "";
    } else if (char === "\n") {
      row.push(cell);
      rows.push(row);
      row = [];
      cell = "";
    } else if (char === "\r") {
      if (input[index + 1] === "\n") index += 1;
      row.push(cell);
      rows.push(row);
      row = [];
      cell = "";
    } else {
      cell += char;
    }
  }

  if (quoted) return null;
  if (cell || row.length > 0) {
    row.push(cell);
    rows.push(row);
  }

  return rows.filter((candidate) => candidate.some((value) => value.trim()));
}

function rowRecord(header: string[], row: string[]): Record<ImportCsvColumn, string> | null {
  const positions = new Map(header.map((column, index) => [column, index]));
  if (importCsvColumns.some((column) => !positions.has(column))) return null;

  return Object.fromEntries(
    importCsvColumns.map((column) => [column, row[positions.get(column)!] ?? ""])
  ) as Record<ImportCsvColumn, string>;
}

export function parseTeamImportCsv(input: string): TeamEntry[] | null {
  const rows = parseCsvRows(input);
  if (!rows || rows.length < 2) return null;

  const [header, ...dataRows] = rows;
  if (!header) return null;

  const entriesById = new Map<string, TeamEntry>();
  for (const row of dataRows) {
    const record = rowRecord(header, row);
    if (!record) return null;
    const source = {
      license: record.source_license.trim(),
      publisher: record.source_publisher.trim(),
      retrieved_at: record.source_retrieved_at.trim(),
      snippet: record.source_snippet.trim(),
      title: record.source_title.trim(),
      url: record.source_url.trim()
    };
    const existing = entriesById.get(record.id.trim());

    if (existing) {
      existing.sources.push(source);
      continue;
    }

    entriesById.set(record.id.trim(), {
      domains: record.domains
        .split(";")
        .map((domain) => domain.trim())
        .filter(Boolean),
      expansion: record.expansion.trim(),
      id: record.id.trim(),
      meaning: record.meaning.trim(),
      sources: [source],
      term: record.term.trim()
    });
  }

  return Array.from(entriesById.values());
}
