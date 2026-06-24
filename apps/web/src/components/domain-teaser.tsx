"use client";

import { ArrowRight, Mail } from "lucide-react";
import { type FormEvent, useState } from "react";

import { Button } from "@/components/ui/button";

export function DomainTeaser() {
  const [email, setEmail] = useState("");
  const [domain, setDomain] = useState("");

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const nextDomain = email.split("@")[1]?.trim().toLowerCase() ?? "";
    setDomain(nextDomain);
  }

  return (
    <section className="grid gap-3 rounded-md border border-input p-4">
      <form className="flex flex-col gap-2 sm:flex-row" onSubmit={handleSubmit}>
        <div className="relative min-w-0 flex-1">
          <Mail className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-foreground/45" />
          <input
            aria-label="Work email"
            className="h-10 w-full rounded-md border border-input bg-background pl-9 pr-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onChange={(event) => setEmail(event.target.value)}
            placeholder="you@company.com"
            type="email"
            value={email}
          />
        </div>
        <Button type="submit">
          <ArrowRight />
          Try my domain
        </Button>
      </form>
      {domain ? (
        <div className="rounded-md border border-input bg-muted-surface p-3 text-sm">
          <p className="font-medium">{domain}</p>
          <p className="text-foreground/65">
            Team mode preview: shared entries, domain defaults, and admin review queue.
          </p>
        </div>
      ) : null}
    </section>
  );
}
