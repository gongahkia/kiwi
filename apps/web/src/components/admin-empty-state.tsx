import { Inbox } from "lucide-react";
import Link from "next/link";

import type { AdminEmptyStateContent } from "@/lib/admin-empty-states";

export function AdminEmptyState({ actionHref, actionLabel, body, title }: AdminEmptyStateContent) {
  return (
    <section className="grid gap-3 rounded-md border border-input p-4" aria-label={title}>
      <div className="flex items-center gap-2">
        <Inbox className="size-4 text-foreground/55" />
        <h2 className="text-lg font-semibold">{title}</h2>
      </div>
      <p className="text-sm leading-6 text-foreground/65">{body}</p>
      <Link className="w-fit rounded-md border border-input px-3 py-2 text-sm" href={actionHref}>
        {actionLabel}
      </Link>
    </section>
  );
}
