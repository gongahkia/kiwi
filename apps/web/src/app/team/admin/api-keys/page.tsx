import Link from "next/link";

import { AdminEmptyState } from "@/components/admin-empty-state";
import { adminEmptyStates } from "@/lib/admin-empty-states";

export default function TeamApiKeysPage() {
  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-4xl gap-6">
        <header className="grid gap-2">
          <Link
            className="text-sm text-foreground/65 underline-offset-4 hover:underline"
            href="/team/admin"
          >
            Team dashboard
          </Link>
          <h1 className="text-4xl font-semibold">API keys</h1>
        </header>
        <AdminEmptyState {...adminEmptyStates.apiKeys} />
      </div>
    </main>
  );
}
