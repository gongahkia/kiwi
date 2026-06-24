const sections = [
  {
    title: "Web app",
    body: "Search sends q, limit, optional context, and optional confidence filters. Suggestions and glossary forms send term, expansion, meaning, domains, source URL, and source title. Hosted wat stores account email, sessions, team membership, personal entries, team entries, suggestions, and audit history."
  },
  {
    title: "Private glossary layers",
    body: "Team and personal entries are private layer data, not public open-source corpus entries. Browser-saved private entries default to proprietary-team or proprietary-personal source labels and stay scoped to the caller's team or user."
  },
  {
    title: "Search logs",
    body: "Hosted search records query hashes, latency, match count, layer hit, and confidence distribution for operations. Raw query text is not required for analytics."
  },
  {
    title: "Browser extension",
    body: "The extension sends the acronym token, lookup limit, account email, team ID, API token header, and bounded context made from hostname, title, and headings. It stores API base URL, account email, token, team ID, domain filters, hover/highlight settings, and recent lookup cache in browser storage."
  },
  {
    title: "Slack",
    body: "Slack sends the explicit slash-command term, selected message text, mention text, or opted-in candidate text plus Slack user ID, wat team ID, and API token header. The scaffold stores rate-limit counters when configured; production installs must store encrypted workspace install tokens."
  },
  {
    title: "MCP",
    body: "MCP tools send the tool input: api_key, term, domain, context, limit, confidence filter, or suggestion fields. The server stores only configured environment values and optional pending suggestion files when writes are enabled."
  },
  {
    title: "Self-host defaults",
    body: "Self-hosted wat has no query logging by default. Operators can add their own logging, but the default deployment should work without sending lookup data to a third-party service."
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
