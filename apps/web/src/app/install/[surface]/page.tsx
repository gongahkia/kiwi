import Link from "next/link";
import { notFound } from "next/navigation";

import { installGuideById, installGuides } from "@/lib/install-guides";

interface InstallSurfacePageProps {
  params: Promise<{ surface: string }>;
}

export function generateStaticParams() {
  return installGuides.map((guide) => ({ surface: guide.id }));
}

export default async function InstallSurfacePage({ params }: InstallSurfacePageProps) {
  const { surface } = await params;
  const guide = installGuideById(surface);
  if (!guide) notFound();

  const Icon = guide.icon;

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <article className="mx-auto grid max-w-3xl gap-8">
        <header className="grid gap-3">
          <Link
            className="text-sm text-foreground/65 underline-offset-4 hover:underline"
            href="/install"
          >
            Back to install paths
          </Link>
          <div className="flex items-center gap-3">
            <Icon className="size-5 text-foreground/60" />
            <h1 className="text-4xl font-semibold">{guide.title}</h1>
          </div>
          <p className="text-lg leading-8 text-foreground/75">{guide.detail}</p>
        </header>

        <section className="grid gap-3 rounded-md border border-input p-4">
          <dl className="grid gap-3 text-sm">
            <div className="grid gap-1 sm:grid-cols-[9rem_1fr]">
              <dt className="text-foreground/65">Role</dt>
              <dd>{guide.role}</dd>
            </div>
            <div className="grid gap-1 sm:grid-cols-[9rem_1fr]">
              <dt className="text-foreground/65">Environment</dt>
              <dd>{guide.environment}</dd>
            </div>
          </dl>
        </section>

        <section className="grid gap-4">
          {guide.steps.map((step, index) => (
            <article className="grid gap-3 rounded-md border border-input p-4" key={step.title}>
              <p className="text-sm text-foreground/55">Step {index + 1}</p>
              <h2 className="text-xl font-semibold">{step.title}</h2>
              <p className="leading-7 text-foreground/75">{step.body}</p>
              {step.code ? (
                <pre className="overflow-x-auto rounded-md border border-input bg-muted-surface p-3 text-sm text-primary">
                  <code>{step.code}</code>
                </pre>
              ) : null}
            </article>
          ))}
        </section>
      </article>
    </main>
  );
}
