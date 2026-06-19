import Link from "next/link";

import { SuggestionReviewQueue } from "@/components/suggestion-review-queue";
import { getSuggestedEdits } from "@/lib/suggestions";

export const dynamic = "force-dynamic";

export default function TeamReviewPage() {
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
        <SuggestionReviewQueue initialSuggestions={getSuggestedEdits()} />
      </div>
    </main>
  );
}
