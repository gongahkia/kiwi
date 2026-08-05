CREATE TABLE "api_keys" (
	"id" text PRIMARY KEY NOT NULL,
	"team_id" text NOT NULL,
	"name" text NOT NULL,
	"key_prefix" text NOT NULL,
	"key_hash" text NOT NULL,
	"scopes" text[] DEFAULT ARRAY[]::text[] NOT NULL,
	"created_by" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_used_at" timestamp with time zone,
	"revoked_at" timestamp with time zone,
	CONSTRAINT "api_keys_key_hash_unique" UNIQUE("key_hash")
);
--> statement-breakpoint
ALTER TABLE "api_keys" ADD CONSTRAINT "api_keys_team_id_teams_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
ALTER TABLE "api_keys" ADD CONSTRAINT "api_keys_created_by_users_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "api_keys_team_id_idx" ON "api_keys" USING btree ("team_id");
--> statement-breakpoint
CREATE INDEX "api_keys_key_prefix_idx" ON "api_keys" USING btree ("key_prefix");
--> statement-breakpoint
CREATE TABLE "rate_limit_buckets" (
	"key" text PRIMARY KEY NOT NULL,
	"scope" text NOT NULL,
	"count" integer DEFAULT 0 NOT NULL,
	"reset_at" timestamp with time zone NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX "rate_limit_buckets_reset_at_idx" ON "rate_limit_buckets" USING btree ("reset_at");
--> statement-breakpoint
ALTER TABLE "audit_log" ADD COLUMN "team_id" text;
--> statement-breakpoint
ALTER TABLE "audit_log" ADD CONSTRAINT "audit_log_team_id_teams_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "audit_log_team_id_at_idx" ON "audit_log" USING btree ("team_id","at");
--> statement-breakpoint
CREATE TABLE "team_entry_sources" (
	"id" text PRIMARY KEY NOT NULL,
	"entry_id" text NOT NULL,
	"position" integer NOT NULL,
	"url" text NOT NULL,
	"title" text NOT NULL,
	"publisher" text NOT NULL,
	"license" text NOT NULL,
	"retrieved_at" timestamp with time zone NOT NULL,
	"snippet" text NOT NULL,
	"source_quality" text DEFAULT 'community' NOT NULL
);
--> statement-breakpoint
ALTER TABLE "team_entry_sources" ADD CONSTRAINT "team_entry_sources_entry_id_team_entries_id_fk" FOREIGN KEY ("entry_id") REFERENCES "public"."team_entries"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "team_entry_sources_entry_id_idx" ON "team_entry_sources" USING btree ("entry_id");
--> statement-breakpoint
CREATE TABLE "personal_entry_sources" (
	"id" text PRIMARY KEY NOT NULL,
	"entry_id" text NOT NULL,
	"position" integer NOT NULL,
	"url" text NOT NULL,
	"title" text NOT NULL,
	"publisher" text NOT NULL,
	"license" text NOT NULL,
	"retrieved_at" timestamp with time zone NOT NULL,
	"snippet" text NOT NULL,
	"source_quality" text DEFAULT 'community' NOT NULL
);
--> statement-breakpoint
ALTER TABLE "personal_entry_sources" ADD CONSTRAINT "personal_entry_sources_entry_id_personal_entries_id_fk" FOREIGN KEY ("entry_id") REFERENCES "public"."personal_entries"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "personal_entry_sources_entry_id_idx" ON "personal_entry_sources" USING btree ("entry_id");
--> statement-breakpoint
CREATE UNIQUE INDEX "team_entries_team_term_expansion_active_idx" ON "team_entries" USING btree ("team_id","term_normalized",(lower(coalesce("expansions"[1], '')))) WHERE "team_entries"."deprecated" = false;
--> statement-breakpoint
CREATE UNIQUE INDEX "personal_entries_user_term_expansion_active_idx" ON "personal_entries" USING btree ("user_id","term_normalized",(lower(coalesce("expansions"[1], '')))) WHERE "personal_entries"."deprecated" = false;
