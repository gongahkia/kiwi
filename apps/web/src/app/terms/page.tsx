const sections = [
  {
    title: "Use",
    body: "Use wat for sourced technical glossary lookup, team overlays, and related integrations. Do not use it to publish fabricated definitions or unlawful content."
  },
  {
    title: "Corpus",
    body: "Public corpus entries must keep source URLs and license tags. Team and personal entries remain scoped to the layer where they were created."
  },
  {
    title: "Self-hosting",
    body: "Self-hosted operators control their deployment, data retention, backups, logs, and access policies."
  },
  {
    title: "Availability",
    body: "Managed hosting may change while the project is early. Self-hosting remains the fallback path for independent operation."
  }
];

export default function TermsPage() {
  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <article className="mx-auto grid max-w-3xl gap-8">
        <header className="grid gap-3">
          <h1 className="text-4xl font-semibold">Terms of service</h1>
          <p className="text-lg leading-8 text-foreground/75">
            These terms define acceptable use for wat-hosted services and project integrations.
          </p>
        </header>
        <div className="grid gap-5">
          {sections.map((section) => (
            <section className="grid gap-2" key={section.title}>
              <h2 className="text-xl font-semibold">{section.title}</h2>
              <p className="leading-7 text-foreground/75">{section.body}</p>
            </section>
          ))}
        </div>
      </article>
    </main>
  );
}
