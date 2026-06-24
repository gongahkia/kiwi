import Link from "next/link";

import { Button } from "@/components/ui/button";
import { installGuides } from "@/lib/install-guides";

export default function InstallPage() {
  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <section className="mx-auto grid max-w-5xl gap-8">
        <header className="grid gap-3">
          <h1 className="text-4xl font-semibold">Install wat</h1>
          <p className="max-w-2xl text-lg leading-8 text-foreground/75">
            Choose the surface that matches the workflow. Each path separates role, environment, and
            setup steps.
          </p>
        </header>
        <div className="grid gap-4 md:grid-cols-2">
          {installGuides.map(({ detail, environment, href, icon: Icon, id, role, title }) => (
            <article className="grid gap-4 rounded-md border border-input p-5" id={id} key={id}>
              <div className="flex items-center gap-3">
                <Icon className="size-5" />
                <h2 className="text-xl font-semibold">{title}</h2>
              </div>
              <p className="text-foreground/70">{detail}</p>
              <dl className="grid gap-1 text-sm text-foreground/65">
                <div>
                  <dt className="inline text-primary">Role: </dt>
                  <dd className="inline">{role}</dd>
                </div>
                <div>
                  <dt className="inline text-primary">Env: </dt>
                  <dd className="inline">{environment}</dd>
                </div>
              </dl>
              <Button asChild className="w-fit">
                <Link href={href}>Open install path</Link>
              </Button>
            </article>
          ))}
        </div>
      </section>
    </main>
  );
}
