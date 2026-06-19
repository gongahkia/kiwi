import Link from "next/link";

import { Button } from "@/components/ui/button";

const plans = [
  {
    title: "Self-hosted OSS",
    price: "Free",
    detail: "Run wat with your own Postgres and private team layers.",
    cta: "Install self-hosted",
    href: "/install#docker"
  },
  {
    title: "Managed",
    price: "Optional",
    detail: "Hosted search, team administration, browser extension sync, Slack, and MCP access.",
    cta: "Join managed waitlist",
    href: "/install"
  }
];

export default function PricingPage() {
  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <section className="mx-auto grid max-w-5xl gap-8">
        <header className="grid gap-3">
          <h1 className="text-4xl font-semibold">Pricing and hosting</h1>
          <p className="max-w-2xl text-lg leading-8 text-foreground/75">
            wat stays usable as free self-hosted software. Managed hosting is optional for teams
            that do not want to operate infrastructure.
          </p>
        </header>
        <div className="grid gap-4 md:grid-cols-2">
          {plans.map((plan) => (
            <article className="grid gap-5 rounded-md border border-input p-5" key={plan.title}>
              <div className="grid gap-2">
                <h2 className="text-2xl font-semibold">{plan.title}</h2>
                <p className="text-3xl font-semibold">{plan.price}</p>
              </div>
              <p className="leading-7 text-foreground/75">{plan.detail}</p>
              <Button asChild className="w-fit">
                <Link href={plan.href}>{plan.cta}</Link>
              </Button>
            </article>
          ))}
        </div>
      </section>
    </main>
  );
}
