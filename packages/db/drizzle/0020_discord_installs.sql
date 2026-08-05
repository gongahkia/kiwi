CREATE TABLE "discord_installs" (
	"id" text PRIMARY KEY NOT NULL,
	"discord_guild_id" text NOT NULL,
	"guild_name" text,
	"team_id" text NOT NULL,
	"application_id" text NOT NULL,
	"bot_user_id" text,
	"installer_discord_user_id" text,
	"admin_role_ids" text[] DEFAULT ARRAY[]::text[] NOT NULL,
	"installed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "discord_installs" ADD CONSTRAINT "discord_installs_team_id_teams_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE UNIQUE INDEX "discord_installs_discord_guild_id_unique_idx" ON "discord_installs" USING btree ("discord_guild_id");
--> statement-breakpoint
CREATE INDEX "discord_installs_team_id_idx" ON "discord_installs" USING btree ("team_id");
