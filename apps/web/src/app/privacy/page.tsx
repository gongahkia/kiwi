const sections = [
  {
    title: "Hosted data",
    body: "Hosted wat stores account email, team membership, team glossary entries, suggestions, and audit history needed to operate the service."
  },
  {
    title: "Search privacy",
    body: "Hosted search may record non-PII operational metadata such as query hashes, latency, layer hit, and confidence distribution. Raw query text is not required for analytics."
  },
  {
    title: "Self-host defaults",
    body: "Self-hosted wat has no query logging by default. Operators can add their own logging, but the default deployment should work without sending lookup data to a third-party service."
  },
  {
    title: "Integrations",
    body: "Browser, Slack, and MCP integrations use configured API endpoints and only send lookup or account data needed for the requested action."
  }
];

export default function PrivacyPage() {
  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <article className="mx-auto grid max-w-3xl gap-8">
        <header className="grid gap-3">
          <h1 className="text-4xl font-semibold">Privacy policy</h1>
          <p className="text-lg leading-8 text-foreground/75">
            This policy describes how wat handles account, team, integration, and lookup data.
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
