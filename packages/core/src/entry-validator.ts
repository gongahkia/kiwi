import { z } from "zod";

import { normalizeTerm } from "./normalize.js";
import { GlossaryEntrySchema } from "./schema.js";

export const ValidatedGlossaryEntrySchema = GlossaryEntrySchema.superRefine((entry, ctx) => {
  if (entry.term_normalized !== normalizeTerm(entry.term)) {
    ctx.addIssue({
      code: "custom",
      message: "term_normalized must equal normalized term",
      path: ["term_normalized"]
    });
  }

  if (new Set(entry.expansions).size !== entry.expansions.length) {
    ctx.addIssue({
      code: "custom",
      message: "expansions must be unique",
      path: ["expansions"]
    });
  }

  if (entry.layer === "public" && entry.team_id != null) {
    ctx.addIssue({
      code: "custom",
      message: "public entries must not have team_id",
      path: ["team_id"]
    });
  }

  if (entry.layer === "team" && !entry.team_id) {
    ctx.addIssue({
      code: "custom",
      message: "team entries must have team_id",
      path: ["team_id"]
    });
  }

  if (entry.layer === "personal" && entry.team_id != null) {
    ctx.addIssue({
      code: "custom",
      message: "personal entries must not have team_id",
      path: ["team_id"]
    });
  }

  if (entry.layer === "public" && entry.sources.length === 0) {
    ctx.addIssue({
      code: "custom",
      message: "public entries must have at least one source",
      path: ["sources"]
    });
  }

  if (
    entry.confidence_tier === "T1" &&
    !entry.sources.some((source) => source.source_quality === "canonical")
  ) {
    ctx.addIssue({
      code: "custom",
      message: "T1 entries must include a canonical source",
      path: ["sources"]
    });
  }

  if (entry.deprecated && !entry.deprecated_reason) {
    ctx.addIssue({
      code: "custom",
      message: "deprecated entries must explain why",
      path: ["deprecated_reason"]
    });
  }

  if (!entry.deprecated && entry.deprecated_reason != null) {
    ctx.addIssue({
      code: "custom",
      message: "active entries must not have deprecated_reason",
      path: ["deprecated_reason"]
    });
  }
});

export type ValidatedGlossaryEntry = z.infer<typeof ValidatedGlossaryEntrySchema>;

export function validateEntry(input: unknown): ValidatedGlossaryEntry {
  return ValidatedGlossaryEntrySchema.parse(input);
}

export function validateEntries(input: unknown[]): ValidatedGlossaryEntry[] {
  return z.array(ValidatedGlossaryEntrySchema).parse(input);
}
