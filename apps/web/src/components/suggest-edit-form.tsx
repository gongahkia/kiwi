"use client";

import { Send } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";

interface SuggestEditFormProps {
  entryId: string;
  initialExpansion: string;
  initialMeaning: string;
  initialSourceUrl: string;
}

export function SuggestEditForm({
  entryId,
  initialExpansion,
  initialMeaning,
  initialSourceUrl
}: SuggestEditFormProps) {
  const [form, setForm] = useState({
    expansion: initialExpansion,
    meaning: initialMeaning,
    source_url: initialSourceUrl
  });
  const [status, setStatus] = useState("");

  function setField(field: keyof typeof form, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  async function submit() {
    setStatus("");
    const response = await fetch(`/term/${entryId}/suggest`, {
      body: JSON.stringify(form),
      headers: { "content-type": "application/json" },
      method: "POST"
    });
    if (!response.ok) {
      setStatus(response.status === 401 ? "Login required" : "Invalid suggestion");
      return;
    }

    const payload = (await response.json()) as { suggestion: { id: string } };
    setStatus(`Queued ${payload.suggestion.id}`);
  }

  return (
    <section className="grid gap-3">
      <h2 className="text-lg font-semibold">Suggest edit</h2>
      <input
        className="h-10 rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
        onChange={(event) => setField("expansion", event.target.value)}
        placeholder="expansion"
        value={form.expansion}
      />
      <textarea
        className="min-h-24 rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
        onChange={(event) => setField("meaning", event.target.value)}
        placeholder="meaning"
        value={form.meaning}
      />
      <input
        className="h-10 rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
        onChange={(event) => setField("source_url", event.target.value)}
        placeholder="source url"
        value={form.source_url}
      />
      <div className="flex flex-wrap items-center gap-3">
        <Button onClick={submit} type="button" variant="outline">
          <Send />
          Submit edit
        </Button>
        {status ? <p className="text-sm text-foreground/65">{status}</p> : null}
      </div>
    </section>
  );
}
