import { Client } from "pg";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

interface CountRow {
  count: number;
  label: string;
}

interface CorpusStats {
  byDomain: CountRow[];
  bySource: CountRow[];
  byTier: CountRow[];
  contemporariesCoveragePct: number;
  total: number;
  withContemporaries: number;
}

const databaseUrl = process.env.WAT_DATABASE_URL ?? process.env.DATABASE_URL;

async function getCorpusStats(): Promise<CorpusStats> {
  const client = new Client({
    connectionString: databaseUrl ?? "postgres://wat:wat@localhost:5432/wat"
  });
  await client.connect();
  try {
    const [summary, bySource, byTier, byDomain] = await Promise.all([
      client.query<{ total: number; with_contemporaries: number }>(`
        select
          count(*)::int as total,
          count(*) filter (where cardinality(contemporaries) > 0)::int as with_contemporaries
        from entries
        where layer = 'public' and deprecated = false
      `),
      client.query<CountRow>(`
        select s.publisher as label, count(distinct e.id)::int as count
        from entries e
        join sources s on s.entry_id = e.id
        where e.layer = 'public' and e.deprecated = false
        group by s.publisher
        order by count desc, label asc
      `),
      client.query<CountRow>(`
        select confidence_tier as label, count(*)::int as count
        from entries
        where layer = 'public' and deprecated = false
        group by confidence_tier
        order by count desc, label asc
      `),
      client.query<CountRow>(`
        select domain as label, count(*)::int as count
        from entries
        cross join unnest(domains) as domain
        where layer = 'public' and deprecated = false
        group by domain
        order by count desc, label asc
      `)
    ]);
    const total = summary.rows[0]?.total ?? 0;
    const withContemporaries = summary.rows[0]?.with_contemporaries ?? 0;

    return {
      byDomain: byDomain.rows,
      bySource: bySource.rows,
      byTier: byTier.rows,
      contemporariesCoveragePct: total > 0 ? Math.round((withContemporaries / total) * 100) : 0,
      total,
      withContemporaries
    };
  } finally {
    await client.end();
  }
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
  const stats = await getCorpusStats();

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-5xl gap-8">
        <header className="grid gap-2">
          <h1 className="text-4xl font-semibold">Corpus stats</h1>
          <p className="text-foreground/70">{stats.total} public entries</p>
        </header>
        <section className="grid gap-2 rounded-md border border-input p-4">
          <h2 className="text-xl font-semibold">Alternatives coverage</h2>
          <p className="text-foreground/70">
            {stats.contemporariesCoveragePct}% of public entries have at least one alternative.
          </p>
          <p className="text-sm text-foreground/55">
            {stats.withContemporaries} / {stats.total} public entries
          </p>
        </section>
        <div className="grid gap-8 lg:grid-cols-3">
          <CountTable rows={stats.bySource} title="By source" />
          <CountTable rows={stats.byTier} title="By tier" />
          <CountTable rows={stats.byDomain} title="By domain" />
        </div>
      </div>
    </main>
  );
}
