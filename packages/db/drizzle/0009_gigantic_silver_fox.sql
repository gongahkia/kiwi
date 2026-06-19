CREATE TABLE "examples" (
	"id" text PRIMARY KEY NOT NULL,
	"entry_id" text NOT NULL,
	"position" integer NOT NULL,
	"body" text NOT NULL
);
--> statement-breakpoint
ALTER TABLE "examples" ADD CONSTRAINT "examples_entry_id_entries_id_fk" FOREIGN KEY ("entry_id") REFERENCES "public"."entries"("id") ON DELETE cascade ON UPDATE no action;