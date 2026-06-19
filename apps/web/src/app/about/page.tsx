const nonGoals = [
  "AI-only unsourced definitions",
  "general English dictionary coverage",
  "required external API for self-hosted lookup",
  "CLI surface"
];

export default function AboutPage() {
  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <article className="mx-auto grid max-w-3xl gap-8">
        <header className="grid gap-3">
          <h1 className="text-4xl font-semibold">About wat</h1>
          <p className="text-lg leading-8 text-foreground/75">
            wat is a layered glossary for technical acronyms, initialisms, jargon, and overloaded
            terms.
          </p>
        </header>

        <section className="grid gap-3">
          <h2 className="text-xl font-semibold">Layered model</h2>
          <p className="leading-7">
            Public entries provide shared sourced definitions. Team entries add
            organization-specific context. Personal entries let each user keep private overrides.
            Lookup merges those layers in personal, team, then public priority order.
          </p>
        </section>

        <section className="grid gap-3">
          <h2 className="text-xl font-semibold">Non-goals</h2>
          <ul className="grid gap-2">
            {nonGoals.map((goal) => (
              <li className="rounded-md border border-input p-3" key={goal}>
                {goal}
              </li>
            ))}
          </ul>
        </section>
      </article>
    </main>
  );
}
