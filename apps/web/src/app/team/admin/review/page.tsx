import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { SuggestionReviewQueue } from "@/components/suggestion-review-queue";
import { sessionUserFromCookieStore } from "@/lib/session";
import { getSuggestedEdits } from "@/lib/suggestions";

export const dynamic = "force-dynamic";

export default async function TeamReviewPage() {
  const session = await sessionUserFromCookieStore(await cookies());
  if (!session?.teamId) redirect("/login?next=/team/admin/review");
  const suggestions = await getSuggestedEdits(session.teamId);

  return (
    <main className="min-h-svh bg-background px-6 py-10 text-foreground">
      <div className="mx-auto grid max-w-5xl gap-6">
        <header className="grid gap-2">
          <Link
            className="text-sm text-foreground/65 underline-offset-4 hover:underline"
            href="/team/admin"
          >
            Team dashboard
          </Link>
          <h1 className="text-4xl font-semibold">Review queue</h1>
        </header>
        <SuggestionReviewQueue initialSuggestions={suggestions} />
      </div>
    </main>
  );
}
