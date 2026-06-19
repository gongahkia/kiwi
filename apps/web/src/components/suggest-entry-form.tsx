"use client";

import { Send } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";

interface SuggestEntryFormProps {
  initialTerm?: string;
}

const emptyForm = {
  domains: "general",
  expansion: "",
  meaning: "",
  source_url: "",
  term: ""
};

export function SuggestEntryForm({ initialTerm = "" }: SuggestEntryFormProps) {
  const [form, setForm] = useState({ ...emptyForm, term: initialTerm });
  const [status, setStatus] = useState("");

  function setField(field: keyof typeof emptyForm, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
  }

  async function submit() {
    setStatus("");
    const response = await fetch("/suggest/api", {
      body: JSON.stringify({
        ...form,
        domains: form.domains
          .split(",")
          .map((domain) => domain.trim())
          .filter(Boolean)
      }),
      headers: { "content-type": "application/json" },
      method: "POST"
    });
    if (!response.ok) {
      setStatus("Invalid suggestion");
      return;
    }

    const payload = (await response.json()) as { suggestion: { id: string } };
    setStatus(`Queued ${payload.suggestion.id}`);
    setForm(emptyForm);
  }

  return (
    <section className="grid gap-4">
      <div className="grid gap-2 sm:grid-cols-2">
        {(["term", "expansion", "domains", "source_url"] as const).map((field) => (
          <input
            className="h-10 rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
            key={field}
            onChange={(event) => setField(field, event.target.value)}
            placeholder={field.replace("_", " ")}
            value={form[field]}
          />
        ))}
        <textarea
          className="min-h-28 rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring sm:col-span-2"
          onChange={(event) => setField("meaning", event.target.value)}
          placeholder="meaning"
          value={form.meaning}
        />
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <Button onClick={submit} type="button">
          <Send />
          Submit
        </Button>
        {status ? <p className="text-sm text-foreground/65">{status}</p> : null}
      </div>
    </section>
  );
}
