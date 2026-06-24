"use client";

import { Plus, Save, Trash2 } from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import { Button } from "@/components/ui/button";
import { validateTeamEntryDraft } from "@/lib/team-entry-form-validation";
import type { TeamEntry } from "@/lib/team-entries";

interface TeamEntryCrudProps {
  apiPath?: string;
  defaultDomains?: string;
  initialEntries: TeamEntry[];
  initialTerm?: string;
  layerLabel?: string;
  sourceLicense?: "proprietary-personal" | "proprietary-team";
  sourceLabel?: string;
}

function idFromTerm(term: string): string {
  return term
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function emptyFormFor(defaultDomains: string, initialTerm = "") {
  const term = initialTerm.trim();
  return {
    domains: defaultDomains,
    expansion: "",
    meaning: "",
    source_url: "",
    term
  };
}

type EntryForm = ReturnType<typeof emptyFormFor>;

function generatedIdFor(
  sourceLabel: string,
  form: EntryForm,
  entries: TeamEntry[],
  editingId: string
): string {
  if (editingId) return editingId;

  const termId = idFromTerm(form.term);
  if (!termId) return "";

  const expansionId = idFromTerm(form.expansion);
  const baseId = [sourceLabel, termId, expansionId].filter(Boolean).join("-");
  const existingIds = new Set(entries.map((entry) => entry.id));
  if (!existingIds.has(baseId)) return baseId;

  let suffix = 2;
  while (existingIds.has(`${baseId}-${suffix}`)) {
    suffix += 1;
  }

  return `${baseId}-${suffix}`;
}

function entryFromForm(
  form: EntryForm,
  id: string,
  sourceLabel: string,
  sourceLicense: string
): TeamEntry {
  const sourceUrl = form.source_url.trim() || `https://wat.local/${sourceLabel}/${id || "draft"}`;
  return {
    domains: form.domains
      .split(",")
      .map((domain) => domain.trim())
      .filter(Boolean),
    expansion: form.expansion,
    id,
    meaning: form.meaning,
    sources: [
      {
        license: sourceLicense,
        publisher: `${sourceLabel} import`,
        retrieved_at: new Date().toISOString(),
        snippet: form.meaning,
        title: `${form.term} ${sourceLabel} source`,
        url: sourceUrl
      }
    ],
    term: form.term
  };
}

export function TeamEntryCrud({
  apiPath = "/team/admin/entries/api",
  defaultDomains = "example.com",
  initialEntries,
  initialTerm = "",
  layerLabel = "team",
  sourceLicense = "proprietary-team",
  sourceLabel = "team"
}: TeamEntryCrudProps) {
  const blankForm = useMemo(() => emptyFormFor(defaultDomains, ""), [defaultDomains]);
  const initialForm = useMemo(
    () => emptyFormFor(defaultDomains, initialTerm),
    [defaultDomains, initialTerm]
  );
  const [entries, setEntries] = useState(initialEntries);
  const [editingId, setEditingId] = useState("");
  const [form, setForm] = useState(initialForm);
  const [serverError, setServerError] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const generatedId = useMemo(
    () => generatedIdFor(sourceLabel, form, entries, editingId),
    [editingId, entries, form, sourceLabel]
  );
  const preview = useMemo(
    () => entryFromForm(form, generatedId, sourceLabel, sourceLicense),
    [form, generatedId, sourceLabel, sourceLicense]
  );
  const validationIssues = useMemo(
    () => validateTeamEntryDraft(preview, entries, editingId),
    [editingId, entries, preview]
  );
  const visibleIssues = submitted
    ? [...validationIssues, ...(serverError ? [serverError] : [])]
    : [];
  const hasDraft = Boolean(preview.id.trim());
  const mergedEntries = useMemo(() => {
    if (!hasDraft) return entries;
    if (editingId) {
      return entries.map((entry) => (entry.id === editingId ? preview : entry));
    }
    if (entries.some((entry) => entry.id === preview.id)) {
      return entries.map((entry) => (entry.id === preview.id ? preview : entry));
    }

    return [...entries, preview];
  }, [editingId, entries, hasDraft, preview]);
  const previewAction = !hasDraft
    ? "Draft"
    : editingId || entries.some((entry) => entry.id === preview.id)
      ? "Update"
      : "Create";

  useEffect(() => {
    setEditingId("");
    setForm(initialForm);
  }, [initialForm]);

  function setField(field: keyof EntryForm, value: string) {
    setServerError("");
    setForm((current) => ({ ...current, [field]: value }));
  }

  function edit(entry: TeamEntry) {
    setServerError("");
    setSubmitted(false);
    setEditingId(entry.id);
    setForm({
      domains: entry.domains.join(", "),
      expansion: entry.expansion,
      meaning: entry.meaning,
      source_url: entry.sources[0]?.url ?? "",
      term: entry.term
    });
  }

  async function save() {
    setSubmitted(true);
    setServerError("");
    if (validationIssues.length > 0) return;

    const entry = entryFromForm(form, generatedId, sourceLabel, sourceLicense);
    const response = await fetch(apiPath, {
      body: JSON.stringify(editingId ? { id: editingId, patch: entry } : entry),
      headers: { "content-type": "application/json" },
      method: editingId ? "PATCH" : "POST"
    });
    if (!response.ok) {
      const payload = (await response.json().catch(() => null)) as {
        error?: string;
        message?: string;
      } | null;
      setServerError(payload?.message ?? payload?.error ?? "save failed");
      return;
    }
    const payload = (await response.json()) as { entry: TeamEntry };
    setEntries((current) =>
      editingId
        ? current.map((item) => (item.id === editingId ? payload.entry : item))
        : [...current, payload.entry]
    );
    setEditingId("");
    setSubmitted(false);
    setForm(blankForm);
  }

  async function remove(id: string) {
    const response = await fetch(`${apiPath}?id=${encodeURIComponent(id)}`, {
      method: "DELETE"
    });
    if (response.ok) {
      setEntries((current) => current.filter((entry) => entry.id !== id));
    }
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_20rem]">
      <section className="grid gap-3">
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
            className="min-h-24 rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring sm:col-span-2"
            onChange={(event) => setField("meaning", event.target.value)}
            placeholder="meaning"
            value={form.meaning}
          />
        </div>
        <p className="text-xs text-foreground/55">Generated ID: {preview.id || "term required"}</p>
        {visibleIssues.length > 0 ? (
          <div
            className="grid gap-1 rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-900 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-100"
            role="alert"
          >
            {visibleIssues.map((issue) => (
              <p key={issue}>{issue}</p>
            ))}
          </div>
        ) : null}
        <Button onClick={save} type="button">
          {editingId ? <Save /> : <Plus />}
          {editingId ? "Save entry" : "Create entry"}
        </Button>
        <p className="text-xs text-foreground/55">
          Created {layerLabel} entries are marked {sourceLicense}, not public open-source corpus
          data.
        </p>
        <div className="grid gap-3">
          {entries.map((entry) => (
            <article className="grid gap-2 rounded-md border border-input p-4" key={entry.id}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="text-lg font-semibold">
                    {entry.term} - {entry.expansion}
                  </p>
                  <p className="text-sm text-foreground/65">{entry.meaning}</p>
                </div>
                <div className="flex gap-2">
                  <Button onClick={() => edit(entry)} size="sm" type="button" variant="outline">
                    Edit
                  </Button>
                  <Button
                    onClick={() => remove(entry.id)}
                    size="icon"
                    type="button"
                    variant="outline"
                  >
                    <Trash2 />
                  </Button>
                </div>
              </div>
            </article>
          ))}
        </div>
      </section>
      <aside className="grid content-start gap-2 rounded-md border border-input p-4">
        <p className="text-sm font-medium text-foreground/65">Live merge preview</p>
        <p className="text-xs text-foreground/55">
          {previewAction} / {mergedEntries.length} {layerLabel} entries
        </p>
        <p className="text-xl font-semibold">
          {preview.term || "TERM"} - {preview.expansion || "Expansion"}
        </p>
        <p className="text-sm text-foreground/70">{preview.meaning || "Meaning"}</p>
        <p className="text-xs text-foreground/55">{preview.domains.join(", ")}</p>
      </aside>
    </div>
  );
}
