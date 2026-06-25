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
  primaryKey,
  text,
  timestamp,
  uniqueIndex
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
    contemporaries: text("contemporaries")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    tsvector: tsvector("tsvector").generatedAlwaysAs(
      sql`setweight(to_tsvector('english'::regconfig, coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("expansions"), '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("aliases"), '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("related_terms"), '')), 'D') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("contemporaries"), '')), 'D')`
    ),
    embedding: vector384("embedding")
  },
  (table) => [
    index("entries_embedding_hnsw_idx").using("hnsw", table.embedding.op("vector_cosine_ops")),
    index("entries_term_normalized_trgm_idx").using("gin", table.termNormalized.op("gin_trgm_ops")),
    index("entries_tsvector_gin_idx").using("gin", table.tsvector),
    uniqueIndex("entries_term_layer_team_unique_idx")
      .on(table.termNormalized, table.layer, table.teamId)
      .where(sql`${table.deprecated} = false`),
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

export const entryEmbeddingJobs = pgTable(
  "entry_embedding_jobs",
  {
    entryId: text("entry_id")
      .primaryKey()
      .references(() => entries.id, { onDelete: "cascade" }),
    reason: text("reason").notNull(),
    status: text("status").notNull().default("pending"),
    requestedAt: timestamp("requested_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
  },
  (table) => [
    check("entry_embedding_jobs_reason_check", sql`${table.reason} in ('insert', 'update')`),
    check(
      "entry_embedding_jobs_status_check",
      sql`${table.status} in ('pending', 'processing', 'done', 'failed')`
    )
  ]
);

export const users = pgTable("users", {
  id: text("id").primaryKey(),
  name: text("name"),
  email: text("email").notNull().unique(),
  emailVerified: timestamp("email_verified", { withTimezone: true }),
  image: text("image"),
  teamId: text("team_id").references(() => teams.id),
  role: userRole("role").notNull().default("member"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
});

export const accounts = pgTable(
  "accounts",
  {
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    type: text("type").notNull(),
    provider: text("provider").notNull(),
    providerAccountId: text("provider_account_id").notNull(),
    refreshToken: text("refresh_token"),
    accessToken: text("access_token"),
    expiresAt: integer("expires_at"),
    tokenType: text("token_type"),
    scope: text("scope"),
    idToken: text("id_token"),
    sessionState: text("session_state")
  },
  (table) => [primaryKey({ columns: [table.provider, table.providerAccountId] })]
);

export const sessions = pgTable("sessions", {
  sessionToken: text("session_token").primaryKey(),
  userId: text("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  expires: timestamp("expires", { withTimezone: true }).notNull()
});

export const verificationTokens = pgTable(
  "verification_tokens",
  {
    identifier: text("identifier").notNull(),
    token: text("token").notNull(),
    expires: timestamp("expires", { withTimezone: true }).notNull()
  },
  (table) => [primaryKey({ columns: [table.identifier, table.token] })]
);

export const apiKeys = pgTable(
  "api_keys",
  {
    id: text("id").primaryKey(),
    teamId: text("team_id")
      .notNull()
      .references(() => teams.id, { onDelete: "cascade" }),
    name: text("name").notNull(),
    keyPrefix: text("key_prefix").notNull(),
    keyHash: text("key_hash").notNull().unique(),
    scopes: text("scopes")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    createdBy: text("created_by").references(() => users.id, { onDelete: "set null" }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    lastUsedAt: timestamp("last_used_at", { withTimezone: true }),
    revokedAt: timestamp("revoked_at", { withTimezone: true })
  },
  (table) => [
    index("api_keys_team_id_idx").on(table.teamId),
    index("api_keys_key_prefix_idx").on(table.keyPrefix)
  ]
);

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
    contemporaries: text("contemporaries")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    tsvector: tsvector("tsvector").generatedAlwaysAs(
      sql`setweight(to_tsvector('english'::regconfig, coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("expansions"), '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("aliases"), '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("related_terms"), '')), 'D') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("contemporaries"), '')), 'D')`
    ),
    embedding: vector384("embedding")
  },
  (table) => [
    check(
      "team_entries_confidence_tier_check",
      sql`${table.confidenceTier} in ('T1', 'T2', 'T3', 'T4')`
    ),
    check("team_entries_layer_check", sql`${table.layer} = 'team'`),
    uniqueIndex("team_entries_team_term_expansion_active_idx")
      .on(table.teamId, table.termNormalized, sql`(lower(coalesce("expansions"[1], '')))`)
      .where(sql`${table.deprecated} = false`)
  ]
);

export const teamEntrySources = pgTable(
  "team_entry_sources",
  {
    id: text("id").primaryKey(),
    entryId: text("entry_id")
      .notNull()
      .references(() => teamEntries.id, { onDelete: "cascade" }),
    position: integer("position").notNull(),
    url: text("url").notNull(),
    title: text("title").notNull(),
    publisher: text("publisher").notNull(),
    license: text("license").notNull(),
    retrievedAt: timestamp("retrieved_at", { withTimezone: true }).notNull(),
    snippet: text("snippet").notNull(),
    sourceQuality: text("source_quality").notNull().default("community")
  },
  (table) => [index("team_entry_sources_entry_id_idx").on(table.entryId)]
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
    contemporaries: text("contemporaries")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    tsvector: tsvector("tsvector").generatedAlwaysAs(
      sql`setweight(to_tsvector('english'::regconfig, coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("expansions"), '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("aliases"), '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("related_terms"), '')), 'D') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("contemporaries"), '')), 'D')`
    ),
    embedding: vector384("embedding")
  },
  (table) => [
    check(
      "personal_entries_confidence_tier_check",
      sql`${table.confidenceTier} in ('T1', 'T2', 'T3', 'T4')`
    ),
    check("personal_entries_layer_check", sql`${table.layer} = 'personal'`),
    uniqueIndex("personal_entries_user_term_expansion_active_idx")
      .on(table.userId, table.termNormalized, sql`(lower(coalesce("expansions"[1], '')))`)
      .where(sql`${table.deprecated} = false`)
  ]
);

export const personalEntrySources = pgTable(
  "personal_entry_sources",
  {
    id: text("id").primaryKey(),
    entryId: text("entry_id")
      .notNull()
      .references(() => personalEntries.id, { onDelete: "cascade" }),
    position: integer("position").notNull(),
    url: text("url").notNull(),
    title: text("title").notNull(),
    publisher: text("publisher").notNull(),
    license: text("license").notNull(),
    retrievedAt: timestamp("retrieved_at", { withTimezone: true }).notNull(),
    snippet: text("snippet").notNull(),
    sourceQuality: text("source_quality").notNull().default("community")
  },
  (table) => [index("personal_entry_sources_entry_id_idx").on(table.entryId)]
);

export const auditLog = pgTable("audit_log", {
  id: text("id").primaryKey(),
  actorId: text("actor_id").references(() => users.id),
  teamId: text("team_id").references(() => teams.id, { onDelete: "cascade" }),
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
  teamId: text("team_id").references(() => teams.id, { onDelete: "cascade" }),
  targetType: text("target_type").notNull(),
  targetId: text("target_id"),
  status: suggestedEditStatus("status").notNull().default("pending"),
  beforeJsonb: jsonb("before_jsonb"),
  afterJsonb: jsonb("after_jsonb").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  reviewedBy: text("reviewed_by").references(() => users.id),
  reviewedAt: timestamp("reviewed_at", { withTimezone: true })
});

export const rateLimitBuckets = pgTable(
  "rate_limit_buckets",
  {
    key: text("key").primaryKey(),
    scope: text("scope").notNull(),
    count: integer("count").notNull().default(0),
    resetAt: timestamp("reset_at", { withTimezone: true }).notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
  },
  (table) => [index("rate_limit_buckets_reset_at_idx").on(table.resetAt)]
);

export const slackInstalls = pgTable(
  "slack_installs",
  {
    id: text("id").primaryKey(),
    slackTeamId: text("slack_team_id").notNull(),
    slackTeamName: text("slack_team_name"),
    enterpriseId: text("enterprise_id"),
    enterpriseName: text("enterprise_name"),
    teamId: text("team_id")
      .notNull()
      .references(() => teams.id, { onDelete: "cascade" }),
    appId: text("app_id").notNull(),
    botUserId: text("bot_user_id").notNull(),
    installerSlackUserId: text("installer_slack_user_id").notNull(),
    botTokenEncrypted: jsonb("bot_token_encrypted").notNull(),
    userTokenEncrypted: jsonb("user_token_encrypted"),
    botScopes: text("bot_scopes")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    userScopes: text("user_scopes")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    installedAt: timestamp("installed_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
  },
  (table) => [
    uniqueIndex("slack_installs_slack_team_id_unique_idx").on(table.slackTeamId),
    index("slack_installs_team_id_idx").on(table.teamId)
  ]
);

export const teamsInstalls = pgTable(
  "teams_installs",
  {
    id: text("id").primaryKey(),
    microsoftTenantId: text("microsoft_tenant_id").notNull(),
    tenantName: text("tenant_name"),
    teamId: text("team_id")
      .notNull()
      .references(() => teams.id, { onDelete: "cascade" }),
    appId: text("app_id").notNull(),
    authType: text("auth_type").notNull(),
    apiSecretRegistrationId: text("api_secret_registration_id"),
    serviceUrl: text("service_url"),
    installedBy: text("installed_by"),
    installedAt: timestamp("installed_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
  },
  (table) => [
    uniqueIndex("teams_installs_microsoft_tenant_id_unique_idx").on(table.microsoftTenantId),
    index("teams_installs_team_id_idx").on(table.teamId),
    check(
      "teams_installs_auth_type_check",
      sql`${table.authType} in ('apiSecretServiceAuth', 'microsoftEntra')`
    )
  ]
);

export const discordInstalls = pgTable(
  "discord_installs",
  {
    id: text("id").primaryKey(),
    discordGuildId: text("discord_guild_id").notNull(),
    guildName: text("guild_name"),
    teamId: text("team_id")
      .notNull()
      .references(() => teams.id, { onDelete: "cascade" }),
    applicationId: text("application_id").notNull(),
    botUserId: text("bot_user_id"),
    installerDiscordUserId: text("installer_discord_user_id"),
    adminRoleIds: text("admin_role_ids")
      .array()
      .notNull()
      .default(sql`ARRAY[]::text[]`),
    installedAt: timestamp("installed_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
  },
  (table) => [
    uniqueIndex("discord_installs_discord_guild_id_unique_idx").on(table.discordGuildId),
    index("discord_installs_team_id_idx").on(table.teamId)
  ]
);
