import { sql } from "drizzle-orm";
import { boolean, check, customType, integer, pgTable, text, timestamp } from "drizzle-orm/pg-core";

const tsvector = customType<{ data: string }>({
  dataType() {
    return "tsvector";
  }
});

const vector384 = customType<{ data: number[] }>({
  dataType() {
    return "vector(384)";
  }
});

export const entries = pgTable(
  "entries",
  {
    id: text("id").primaryKey(),
    term: text("term").notNull(),
    termNormalized: text("term_normalized").notNull(),
    expansions: text("expansions")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    domains: text("domains")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    meaningShort: text("meaning_short").notNull(),
    meaningLong: text("meaning_long").notNull(),
    coiner: text("coiner"),
    yearCoined: integer("year_coined"),
    confidenceTier: text("confidence_tier").notNull(),
    license: text("license").notNull(),
    layer: text("layer").notNull().default("public"),
    teamId: text("team_id"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
    deprecated: boolean("deprecated").notNull().default(false),
    deprecatedReason: text("deprecated_reason"),
    aliases: text("aliases")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    relatedTerms: text("related_terms")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    tsvector: tsvector("tsvector").generatedAlwaysAs(
      sql`setweight(to_tsvector('english', coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english', coalesce(array_to_string("expansions", ' '), '')), 'A') ||
          setweight(to_tsvector('english', coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english', coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english', coalesce(array_to_string("aliases", ' '), '')), 'B') ||
          setweight(to_tsvector('english', coalesce(array_to_string("related_terms", ' '), '')), 'D')`
    ),
    embedding: vector384("embedding")
  },
  (table) => [
    check(
      "entries_confidence_tier_check",
      sql`${table.confidenceTier} in ('T1', 'T2', 'T3', 'T4')`
    ),
    check("entries_layer_check", sql`${table.layer} in ('public', 'team', 'personal')`)
  ]
);
