import { getHealthSnapshot } from "@/lib/health";

export default function StatusPage() {
  const health = getHealthSnapshot();

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <section className="mx-auto grid max-w-3xl gap-6">
        <header className="grid gap-3">
          <h1 className="text-4xl font-semibold">Status</h1>
          <p className="text-lg leading-8 text-foreground/75">
            Current service status from the web health check.
          </p>
        </header>
        <div className="grid gap-3 rounded-md border border-input p-5">
          <div className="flex items-center gap-3">
            <span className="size-3 rounded-sm bg-primary" />
            <p className="text-2xl font-semibold">Operational</p>
          </div>
          <dl className="grid gap-2 text-sm text-foreground/70">
            <div className="flex justify-between gap-4">
              <dt>Service</dt>
              <dd>{health.service}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt>Status</dt>
              <dd>{health.status}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt>Checked</dt>
              <dd>{health.checked_at}</dd>
            </div>
          </dl>
        </div>
      </section>
    </main>
  );
}
