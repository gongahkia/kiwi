CREATE TABLE "teams" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"email_domain" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"settings_jsonb" jsonb DEFAULT '{}'::jsonb NOT NULL,
	CONSTRAINT "teams_email_domain_unique" UNIQUE("email_domain")
);
