CREATE TYPE "public"."suggested_edit_status" AS ENUM('pending', 'approved', 'rejected');--> statement-breakpoint
CREATE TABLE "suggested_edits" (
	"id" text PRIMARY KEY NOT NULL,
	"actor_id" text,
	"target_type" text NOT NULL,
	"target_id" text,
	"status" "suggested_edit_status" DEFAULT 'pending' NOT NULL,
	"before_jsonb" jsonb,
	"after_jsonb" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"reviewed_by" text,
	"reviewed_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "suggested_edits" ADD CONSTRAINT "suggested_edits_actor_id_users_id_fk" FOREIGN KEY ("actor_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "suggested_edits" ADD CONSTRAINT "suggested_edits_reviewed_by_users_id_fk" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;
