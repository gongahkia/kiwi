import { sourceInventoryFromEntries, type SourceInventoryRow } from "@/lib/source-inventory";
import { getPublicCorpusEntries } from "@/lib/public-corpus";

async function getSources(): Promise<SourceInventoryRow[]> {
  return sourceInventoryFromEntries(await getPublicCorpusEntries());
}

export default async function SourcesPage() {
  const sources = await getSources();

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <section className="mx-auto grid max-w-5xl gap-6">
        <header className="grid gap-2">
          <h1 className="text-4xl font-semibold">Sources</h1>
          <p className="text-foreground/70">{sources.length} public source URLs</p>
        </header>
        <div className="overflow-x-auto rounded-md border border-input">
          <table className="w-full border-collapse text-left text-sm">
            <thead className="bg-secondary">
              <tr>
                <th className="p-3 font-medium">Source</th>
                <th className="p-3 font-medium">License</th>
                <th className="p-3 font-medium">Policy</th>
                <th className="p-3 font-medium">Last refresh</th>
                <th className="p-3 font-medium">Entries</th>
                <th className="p-3 font-medium">Status</th>
              </tr>
            </thead>
            <tbody>
              {sources.map((source) => (
                <tr className="border-t border-input" key={source.url}>
                  <td className="p-3">
                    <a className="font-medium underline underline-offset-4" href={source.url}>
                      {source.title}
                    </a>
                    <p className="text-foreground/60">{source.publisher}</p>
                  </td>
                  <td className="p-3">{source.license}</td>
                  <td className="p-3">{source.license_policy}</td>
                  <td className="p-3">{source.retrieved_at}</td>
                  <td className="p-3">{source.count}</td>
                  <td className="p-3">{source.failure_status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  );
}
