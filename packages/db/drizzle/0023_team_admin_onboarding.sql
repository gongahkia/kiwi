ALTER TABLE "team_entries" ADD COLUMN "review_status" text DEFAULT 'active' NOT NULL;
--> statement-breakpoint
ALTER TABLE "search_events" ADD COLUMN "result_terms" text[] DEFAULT ARRAY[]::text[] NOT NULL;
--> statement-breakpoint
ALTER TABLE "team_entries" ADD CONSTRAINT "team_entries_review_status_check" CHECK ("team_entries"."review_status" in ('active', 'needs_review', 'stale'));
--> statement-breakpoint
ALTER TABLE "personal_entries" ADD COLUMN "review_status" text DEFAULT 'active' NOT NULL;
--> statement-breakpoint
ALTER TABLE "personal_entries" ADD CONSTRAINT "personal_entries_review_status_check" CHECK ("personal_entries"."review_status" in ('active', 'needs_review', 'stale'));
--> statement-breakpoint
CREATE TABLE "team_invites" (
	"id" text PRIMARY KEY NOT NULL,
	"team_id" text NOT NULL,
	"email" text NOT NULL,
	"role" "user_role" DEFAULT 'member' NOT NULL,
	"token_hash" text NOT NULL,
	"invited_by" text,
	"accepted_by" text,
	"accepted_at" timestamp with time zone,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "team_invites_token_hash_unique" UNIQUE("token_hash")
);
--> statement-breakpoint
ALTER TABLE "team_invites" ADD CONSTRAINT "team_invites_team_id_teams_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
ALTER TABLE "team_invites" ADD CONSTRAINT "team_invites_invited_by_users_id_fk" FOREIGN KEY ("invited_by") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;
--> statement-breakpoint
ALTER TABLE "team_invites" ADD CONSTRAINT "team_invites_accepted_by_users_id_fk" FOREIGN KEY ("accepted_by") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "team_invites_team_email_pending_idx" ON "team_invites" USING btree ("team_id","email","accepted_at","expires_at");
--> statement-breakpoint
CREATE INDEX "team_invites_email_pending_idx" ON "team_invites" USING btree ("email","accepted_at","expires_at");
