import { z } from "zod";

export const SourceQualitySchema = z.enum(["canonical", "secondary", "community"]);

export const SourceCitationSchema = z.object({
  url: z.string().url(),
  title: z.string().min(1),
  publisher: z.string().min(1),
  license: z.string().min(1),
  retrieved_at: z.string().datetime({ offset: true }),
  snippet: z.string().min(1),
  source_quality: SourceQualitySchema
});

export type SourceQuality = z.infer<typeof SourceQualitySchema>;
export type SourceCitation = z.infer<typeof SourceCitationSchema>;
