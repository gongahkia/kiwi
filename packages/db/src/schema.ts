import { sql } from "drizzle-orm";
import {
  boolean,
  check,
  customType,
  index,
  integer,
  pgEnum,
  jsonb,
  pgTable,
  text,
  timestamp
} from "drizzle-orm/pg-core";

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

export const userRole = pgEnum("user_role", ["admin", "member"]);
export const suggestedEditStatus = pgEnum("suggested_edit_status", [
  "pending",
  "approved",
  "rejected"
]);

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
      sql`setweight(to_tsvector('english'::regconfig, coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("expansions"), '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("aliases"), '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("related_terms"), '')), 'D')`
    ),
    embedding: vector384("embedding")
  },
  (table) => [
    index("entries_tsvector_gin_idx").using("gin", table.tsvector),
    check(
      "entries_confidence_tier_check",
      sql`${table.confidenceTier} in ('T1', 'T2', 'T3', 'T4')`
    ),
    check("entries_layer_check", sql`${table.layer} in ('public', 'team', 'personal')`)
  ]
);

export const teams = pgTable("teams", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  emailDomain: text("email_domain").notNull().unique(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  settingsJsonb: jsonb("settings_jsonb")
    .notNull()
    .default(sql`'{}'::jsonb`)
});

export const sources = pgTable(
  "sources",
  {
    id: text("id").primaryKey(),
    entryId: text("entry_id")
      .notNull()
      .references(() => entries.id, { onDelete: "cascade" }),
    position: integer("position").notNull(),
    url: text("url").notNull(),
    title: text("title").notNull(),
    publisher: text("publisher").notNull(),
    license: text("license").notNull(),
    retrievedAt: timestamp("retrieved_at", { withTimezone: true }).notNull(),
    snippet: text("snippet").notNull(),
    sourceQuality: text("source_quality").notNull()
  },
  (table) => [
    check(
      "sources_source_quality_check",
      sql`${table.sourceQuality} in ('canonical', 'secondary', 'community')`
    )
  ]
);

export const examples = pgTable("examples", {
  id: text("id").primaryKey(),
  entryId: text("entry_id")
    .notNull()
    .references(() => entries.id, { onDelete: "cascade" }),
  position: integer("position").notNull(),
  body: text("body").notNull()
});

export const users = pgTable("users", {
  id: text("id").primaryKey(),
  email: text("email").notNull().unique(),
  teamId: text("team_id").references(() => teams.id),
  role: userRole("role").notNull().default("member"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
});

export const teamEntries = pgTable(
  "team_entries",
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
    layer: text("layer").notNull().default("team"),
    teamId: text("team_id")
      .notNull()
      .references(() => teams.id, { onDelete: "cascade" }),
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
      sql`setweight(to_tsvector('english'::regconfig, coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("expansions"), '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("aliases"), '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("related_terms"), '')), 'D')`
    ),
    embedding: vector384("embedding")
  },
  (table) => [
    check(
      "team_entries_confidence_tier_check",
      sql`${table.confidenceTier} in ('T1', 'T2', 'T3', 'T4')`
    ),
    check("team_entries_layer_check", sql`${table.layer} = 'team'`)
  ]
);

export const personalEntries = pgTable(
  "personal_entries",
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
    layer: text("layer").notNull().default("personal"),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
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
      sql`setweight(to_tsvector('english'::regconfig, coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("expansions"), '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("aliases"), '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("related_terms"), '')), 'D')`
    ),
    embedding: vector384("embedding")
  },
  (table) => [
    check(
      "personal_entries_confidence_tier_check",
      sql`${table.confidenceTier} in ('T1', 'T2', 'T3', 'T4')`
    ),
    check("personal_entries_layer_check", sql`${table.layer} = 'personal'`)
  ]
);

export const auditLog = pgTable("audit_log", {
  id: text("id").primaryKey(),
  actorId: text("actor_id").references(() => users.id),
  action: text("action").notNull(),
  targetType: text("target_type").notNull(),
  targetId: text("target_id").notNull(),
  beforeJsonb: jsonb("before_jsonb"),
  afterJsonb: jsonb("after_jsonb"),
  at: timestamp("at", { withTimezone: true }).notNull().defaultNow()
});

export const suggestedEdits = pgTable("suggested_edits", {
  id: text("id").primaryKey(),
  actorId: text("actor_id").references(() => users.id),
  targetType: text("target_type").notNull(),
  targetId: text("target_id"),
  status: suggestedEditStatus("status").notNull().default("pending"),
  beforeJsonb: jsonb("before_jsonb"),
  afterJsonb: jsonb("after_jsonb").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  reviewedBy: text("reviewed_by").references(() => users.id),
  reviewedAt: timestamp("reviewed_at", { withTimezone: true })
});
