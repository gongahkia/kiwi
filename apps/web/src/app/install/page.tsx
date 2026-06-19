import Link from "next/link";
import { Box, Cable, Globe, MessageSquare } from "lucide-react";

import { Button } from "@/components/ui/button";

const surfaces = [
  {
    id: "browser-extension",
    title: "Browser extension",
    href: "/extensions/browser",
    icon: Globe,
    detail: "Hover explanations and page-context lookup."
  },
  {
    id: "slack",
    title: "Slack",
    href: "/apps/slack",
    icon: MessageSquare,
    detail: "Slash commands and message shortcuts."
  },
  {
    id: "mcp",
    title: "MCP",
    href: "/apps/mcp",
    icon: Cable,
    detail: "Agent lookup tools over stdio."
  },
  {
    id: "docker",
    title: "Docker",
    href: "/docs/self-host",
    icon: Box,
    detail: "Self-host web, workers, and Postgres."
  }
];

export default function InstallPage() {
  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <section className="mx-auto grid max-w-5xl gap-8">
        <header className="grid gap-3">
          <h1 className="text-4xl font-semibold">Install wat</h1>
          <p className="max-w-2xl text-lg leading-8 text-foreground/75">
            Choose the surface that matches the workflow: browser, Slack, MCP, or self-hosted
            Docker.
          </p>
        </header>
        <div className="grid gap-4 md:grid-cols-2">
          {surfaces.map(({ detail, href, icon: Icon, id, title }) => (
            <article className="grid gap-4 rounded-md border border-input p-5" id={id} key={id}>
              <div className="flex items-center gap-3">
                <Icon className="size-5" />
                <h2 className="text-xl font-semibold">{title}</h2>
              </div>
              <p className="text-foreground/70">{detail}</p>
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
