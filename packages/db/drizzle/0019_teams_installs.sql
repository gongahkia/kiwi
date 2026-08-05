CREATE TABLE "teams_installs" (
	"id" text PRIMARY KEY NOT NULL,
	"microsoft_tenant_id" text NOT NULL,
	"tenant_name" text,
	"team_id" text NOT NULL,
	"app_id" text NOT NULL,
	"auth_type" text NOT NULL,
	"api_secret_registration_id" text,
	"service_url" text,
	"installed_by" text,
	"installed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "teams_installs" ADD CONSTRAINT "teams_installs_team_id_teams_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE UNIQUE INDEX "teams_installs_microsoft_tenant_id_unique_idx" ON "teams_installs" USING btree ("microsoft_tenant_id");
--> statement-breakpoint
CREATE INDEX "teams_installs_team_id_idx" ON "teams_installs" USING btree ("team_id");
--> statement-breakpoint
ALTER TABLE "teams_installs" ADD CONSTRAINT "teams_installs_auth_type_check" CHECK ("teams_installs"."auth_type" in ('apiSecretServiceAuth', 'microsoftEntra'));
