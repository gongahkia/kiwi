CREATE TABLE "slack_installs" (
	"id" text PRIMARY KEY NOT NULL,
	"slack_team_id" text NOT NULL,
	"slack_team_name" text,
	"enterprise_id" text,
	"enterprise_name" text,
	"team_id" text NOT NULL,
	"app_id" text NOT NULL,
	"bot_user_id" text NOT NULL,
	"installer_slack_user_id" text NOT NULL,
	"bot_token_encrypted" jsonb NOT NULL,
	"user_token_encrypted" jsonb,
	"bot_scopes" text[] DEFAULT ARRAY[]::text[] NOT NULL,
	"user_scopes" text[] DEFAULT ARRAY[]::text[] NOT NULL,
	"installed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "slack_installs" ADD CONSTRAINT "slack_installs_team_id_teams_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE UNIQUE INDEX "slack_installs_slack_team_id_unique_idx" ON "slack_installs" USING btree ("slack_team_id");
--> statement-breakpoint
CREATE INDEX "slack_installs_team_id_idx" ON "slack_installs" USING btree ("team_id");
