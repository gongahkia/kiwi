import { z } from "zod";

import { LicenseIdSchema } from "./license.js";

export const SourceQualitySchema = z.enum(["canonical", "secondary", "community"]);

export const SourceCitationSchema = z.object({
  url: z.string().url(),
  title: z.string().min(1),
  publisher: z.string().min(1),
  license: LicenseIdSchema,
  retrieved_at: z.string().datetime({ offset: true }),
  snippet: z.string().min(1),
  source_quality: SourceQualitySchema
});

export const ConfidenceTierSchema = z.enum(["T1", "T2", "T3", "T4"]);
export const EntryLayerSchema = z.enum(["public", "team", "personal"]);

export const GlossaryEntrySchema = z.object({
  id: z.string().min(1),
  term: z.string().min(1),
  term_normalized: z.string().min(1),
  expansions: z.array(z.string().min(1)),
  domains: z.array(z.string().min(1)),
  meaning_short: z.string().min(1),
  meaning_long: z.string().min(1),
  examples: z.array(z.string().min(1)),
  sources: z.array(SourceCitationSchema),
  coiner: z.string().min(1).nullable(),
  year_coined: z.number().int().nonnegative().nullable(),
  confidence_tier: ConfidenceTierSchema,
  license: LicenseIdSchema,
  layer: EntryLayerSchema,
  team_id: z.string().min(1).nullable().optional(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }),
  deprecated: z.boolean(),
  deprecated_reason: z.string().min(1).nullable(),
  aliases: z.array(z.string().min(1)),
  related_terms: z.array(z.string().min(1)),
  contemporaries: z.array(z.string().min(1))
});

export type SourceQuality = z.infer<typeof SourceQualitySchema>;
export type SourceCitation = z.infer<typeof SourceCitationSchema>;
export type ConfidenceTier = z.infer<typeof ConfidenceTierSchema>;
export type EntryLayer = z.infer<typeof EntryLayerSchema>;
export type GlossaryEntry = z.infer<typeof GlossaryEntrySchema>;
