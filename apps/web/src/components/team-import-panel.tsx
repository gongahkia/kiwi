"use client";

import { Upload } from "lucide-react";
import { useMemo, useState } from "react";

import { Button } from "@/components/ui/button";
import { previewTeamImport, type TeamImportFormat } from "@/lib/team-import-preview";
import type { TeamEntry } from "@/lib/team-entries";

type ImportResolution = "skip" | "update";

interface TeamImportPanelProps {
  existingEntries: TeamEntry[];
}

export function TeamImportPanel({ existingEntries }: TeamImportPanelProps) {
  const [format, setFormat] = useState<TeamImportFormat>("json");
  const [input, setInput] = useState("");
  const [resolutions, setResolutions] = useState<Record<string, ImportResolution>>({});
  const [result, setResult] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const preview = useMemo(
    () => previewTeamImport(input, format, existingEntries),
    [existingEntries, format, input]
  );
  const rowsToCreate = preview.rows.filter((row) => !row.conflict).map((row) => row.entry);
  const rowsToUpdate = preview.rows.filter(
    (row) => row.conflict && resolutions[row.entry.id] === "update"
  );
  const skippedConflicts = preview.conflicts.length - rowsToUpdate.length;

  async function readFile(file: File | null) {
    if (!file) return;
    setResult("");
    setResolutions({});
    setInput(await file.text());
    if (file.name.toLowerCase().endsWith(".csv")) setFormat("csv");
    if (file.name.toLowerCase().endsWith(".json")) setFormat("json");
  }

  async function importAccepted() {
    setSubmitting(true);
    setResult("");
    try {
      let inserted = 0;
      let skipped = 0;
      if (rowsToCreate.length > 0) {
        const response = await fetch("/team/admin/import/api", {
          body: JSON.stringify({ entries: rowsToCreate }),
          headers: { "content-type": "application/json", "x-wat-same-origin": "1" },
          method: "POST"
        });
        const body = (await response.json()) as {
          error?: string;
          inserted?: number;
          skipped?: number;
        };
        if (!response.ok) {
          setResult(body.error ?? "import failed");
          return;
        }
        inserted = body.inserted ?? 0;
        skipped = body.skipped ?? 0;
      }

      let updated = 0;
      for (const row of rowsToUpdate) {
        const response = await fetch("/team/admin/entries/api", {
          body: JSON.stringify({ id: row.conflict!.existingId, patch: row.entry }),
          headers: { "content-type": "application/json", "x-wat-same-origin": "1" },
          method: "PATCH"
        });
        if (!response.ok) {
          const body = (await response.json().catch(() => null)) as { error?: string } | null;
          setResult(body?.error ?? "update failed");
          return;
        }
        updated += 1;
      }

      setResult(`Imported ${inserted}; updated ${updated}; skipped ${skipped + skippedConflicts}.`);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="grid gap-4 rounded-md border border-input p-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="grid gap-1">
          <h2 className="text-xl font-semibold">Upload glossary</h2>
          <p className="text-sm text-foreground/65">
            Paste JSON/CSV or choose a file; valid rows can be imported while errors stay visible.
          </p>
        </div>
        <div className="flex gap-2">
          <Button
            onClick={() => setFormat("json")}
            size="sm"
            type="button"
            variant={format === "json" ? "default" : "outline"}
          >
            JSON
          </Button>
          <Button
            onClick={() => setFormat("csv")}
            size="sm"
            type="button"
            variant={format === "csv" ? "default" : "outline"}
          >
            CSV
          </Button>
        </div>
      </div>

      <label className="grid gap-2 text-sm">
        <span className="text-foreground/65">Import file</span>
        <input
          accept=".json,.csv,application/json,text/csv"
          className="rounded-md border border-input p-2 text-sm"
          onChange={(event) => void readFile(event.target.files?.[0] ?? null)}
          type="file"
        />
      </label>

      <textarea
        className="min-h-72 rounded-md border border-input bg-background px-3 py-2 font-mono text-xs outline-none focus-visible:ring-2 focus-visible:ring-ring"
        onChange={(event) => {
          setResult("");
          setResolutions({});
          setInput(event.target.value);
        }}
        placeholder={format === "json" ? '{"entries": [...]}' : "id,term,expansion,..."}
        value={input}
      />

      <div className="grid gap-3 rounded-md border border-input bg-muted-surface p-3 text-sm">
        <p>
          Preview: {preview.accepted.length} accepted / {preview.issues.length} errors /{" "}
          {preview.total} total.
        </p>
        {preview.conflicts.length > 0 ? (
          <p>
            Dry run found {preview.conflicts.length} duplicate conflict
            {preview.conflicts.length === 1 ? "" : "s"}. Choose update or skip before import.
          </p>
        ) : null}
        {preview.issues.length > 0 ? (
          <ul className="grid gap-1">
            {preview.issues.map((issue) => (
              <li key={`${issue.entryId}-${issue.message}`}>
                {issue.entryId}: {issue.message}
              </li>
            ))}
          </ul>
        ) : null}
        {preview.accepted.length > 0 ? (
          <ul className="grid gap-1 text-foreground/70">
            {preview.rows.map(({ conflict, entry }) => (
              <li className="grid gap-2 sm:grid-cols-[1fr_auto]" key={entry.id}>
                <span>
                  {entry.term} - {entry.expansion}
                  {conflict ? ` / conflict: ${conflict.reason}` : " / create"}
                </span>
                {conflict ? (
                  <span className="flex gap-2">
                    <Button
                      onClick={() =>
                        setResolutions((current) => ({ ...current, [entry.id]: "update" }))
                      }
                      size="sm"
                      type="button"
                      variant={resolutions[entry.id] === "update" ? "default" : "outline"}
                    >
                      Update
                    </Button>
                    <Button
                      onClick={() =>
                        setResolutions((current) => ({ ...current, [entry.id]: "skip" }))
                      }
                      size="sm"
                      type="button"
                      variant={resolutions[entry.id] === "skip" ? "default" : "outline"}
                    >
                      Skip
                    </Button>
                  </span>
                ) : (
                  <span>
                    <Button disabled size="sm" type="button" variant="outline">
                      Create
                    </Button>
                  </span>
                )}
              </li>
            ))}
          </ul>
        ) : null}
      </div>

      <Button
        disabled={rowsToCreate.length + rowsToUpdate.length === 0 || submitting}
        onClick={() => void importAccepted()}
        type="button"
      >
        <Upload />
        {submitting ? "Importing" : "Import accepted rows"}
      </Button>
      {result ? <p className="text-sm text-foreground/65">{result}</p> : null}
    </section>
  );
}
