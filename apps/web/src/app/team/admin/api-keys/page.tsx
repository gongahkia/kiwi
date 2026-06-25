import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { AdminEmptyState } from "@/components/admin-empty-state";
import { ApiKeysPanel } from "@/components/api-keys-panel";
import { adminEmptyStates } from "@/lib/admin-empty-states";
import { listApiKeys } from "@/lib/api-keys";
import { sessionUserFromCookieStore } from "@/lib/session";

export default async function TeamApiKeysPage() {
  const session = await sessionUserFromCookieStore(await cookies());
  if (!session?.teamId) redirect("/login?next=/team/admin/api-keys");
  const keys = await listApiKeys(session.teamId);

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
        {keys.length === 0 ? <AdminEmptyState {...adminEmptyStates.apiKeys} /> : null}
        <ApiKeysPanel initialKeys={keys} />
      </div>
    </main>
  );
}
