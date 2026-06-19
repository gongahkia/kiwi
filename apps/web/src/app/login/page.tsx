export default async function LoginPage({
  searchParams
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next = "/" } = await searchParams;

  return (
    <main className="grid min-h-svh place-items-center bg-background p-6 text-foreground">
      <section className="grid w-full max-w-sm gap-3">
        <h1 className="text-2xl font-semibold">Login</h1>
        <p className="text-sm text-foreground/70">Continue to {next}</p>
      </section>
    </main>
  );
}
