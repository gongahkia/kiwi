import { readFile } from "node:fs/promises";
import { join } from "node:path";

interface CorpusEntry {
  confidence_tier: string;
  domains: string[];
  layer: string;
  sources: {
    publisher: string;
  }[];
}

interface CountRow {
  count: number;
  label: string;
}

async function getEntries(): Promise<CorpusEntry[]> {
  const seedJson = await readSeedJson();
  const parsed = JSON.parse(seedJson) as { entries: CorpusEntry[] };
  return parsed.entries.filter((entry) => entry.layer === "public");
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

function countValues(values: string[]): CountRow[] {
  const counts = new Map<string, number>();

  for (const value of values) {
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }

  return Array.from(counts, ([label, count]) => ({ label, count })).sort(
    (left, right) => right.count - left.count || left.label.localeCompare(right.label)
  );
}

function CountTable({ rows, title }: { rows: CountRow[]; title: string }) {
  return (
    <section className="grid gap-3">
      <h2 className="text-xl font-semibold">{title}</h2>
      <div className="overflow-x-auto rounded-md border border-input">
        <table className="w-full border-collapse text-left text-sm">
          <thead className="bg-secondary">
            <tr>
              <th className="px-3 py-2 font-medium">Name</th>
              <th className="px-3 py-2 text-right font-medium">Entries</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr className="border-t border-input" key={row.label}>
                <td className="px-3 py-2">{row.label}</td>
                <td className="px-3 py-2 text-right tabular-nums">{row.count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

export default async function StatsPage() {
  const entries = await getEntries();
  const bySource = countValues(
    entries.flatMap((entry) => Array.from(new Set(entry.sources.map((source) => source.publisher))))
  );
  const byTier = countValues(entries.map((entry) => entry.confidence_tier));
  const byDomain = countValues(entries.flatMap((entry) => entry.domains));

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-5xl gap-8">
        <header className="grid gap-2">
          <h1 className="text-4xl font-semibold">Corpus stats</h1>
          <p className="text-foreground/70">{entries.length} public entries</p>
        </header>
        <div className="grid gap-8 lg:grid-cols-3">
          <CountTable rows={bySource} title="By source" />
          <CountTable rows={byTier} title="By tier" />
          <CountTable rows={byDomain} title="By domain" />
        </div>
      </div>
    </main>
  );
}
