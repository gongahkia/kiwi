"use client";

import { Check, Save, X } from "lucide-react";
import { useState } from "react";

import { AdminEmptyState } from "@/components/admin-empty-state";
import { Button } from "@/components/ui/button";
import { adminEmptyStates } from "@/lib/admin-empty-states";
import type { SuggestedEdit, SuggestedEditStatus } from "@/lib/suggestions";

interface SuggestionReviewQueueProps {
  initialSuggestions: SuggestedEdit[];
}

export function SuggestionReviewQueue({ initialSuggestions }: SuggestionReviewQueueProps) {
  const [suggestions, setSuggestions] = useState(initialSuggestions);
  const [drafts, setDrafts] = useState<Record<string, string>>(() =>
    Object.fromEntries(
      initialSuggestions.map((suggestion) => [
        suggestion.id,
        JSON.stringify(suggestion.after_jsonb, null, 2)
      ])
    )
  );

  function setDraft(id: string, value: string) {
    setDrafts((current) => ({ ...current, [id]: value }));
  }

  async function review(id: string, status: SuggestedEditStatus) {
    let after_jsonb: unknown;
    try {
      after_jsonb = JSON.parse(drafts[id] ?? "{}");
    } catch {
      return;
    }

    const response = await fetch("/team/admin/review/api", {
      body: JSON.stringify({ after_jsonb, id, status }),
      headers: { "content-type": "application/json", "x-wat-same-origin": "1" },
      method: "PATCH"
    });
    if (!response.ok) return;

    const payload = (await response.json()) as { suggestion: SuggestedEdit };
    setSuggestions((current) =>
      current.map((suggestion) => (suggestion.id === id ? payload.suggestion : suggestion))
    );
  }

  return (
    <section className="grid gap-4">
      {suggestions.map((suggestion) => (
        <article className="grid gap-3 rounded-md border border-input p-4" key={suggestion.id}>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="font-semibold">{suggestion.target_id ?? "New entry"}</p>
              <p className="text-sm text-foreground/65">
                {suggestion.actor_id} / {suggestion.status}
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button onClick={() => review(suggestion.id, "pending")} size="sm" variant="outline">
                <Save />
                Save
              </Button>
              <Button onClick={() => review(suggestion.id, "approved")} size="sm" type="button">
                <Check />
                Approve
              </Button>
              <Button onClick={() => review(suggestion.id, "rejected")} size="sm" variant="outline">
                <X />
                Reject
              </Button>
            </div>
          </div>
          <textarea
            className="min-h-40 rounded-md border border-input bg-background px-3 py-2 font-mono text-xs outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onChange={(event) => setDraft(suggestion.id, event.target.value)}
            value={drafts[suggestion.id] ?? ""}
          />
        </article>
      ))}
      {suggestions.length === 0 ? <AdminEmptyState {...adminEmptyStates.suggestions} /> : null}
    </section>
  );
}
