CREATE TABLE "sources" (
	"id" text PRIMARY KEY NOT NULL,
	"entry_id" text NOT NULL,
	"position" integer NOT NULL,
	"url" text NOT NULL,
	"title" text NOT NULL,
	"publisher" text NOT NULL,
	"license" text NOT NULL,
	"retrieved_at" timestamp with time zone NOT NULL,
	"snippet" text NOT NULL,
	"source_quality" text NOT NULL,
	CONSTRAINT "sources_source_quality_check" CHECK ("sources"."source_quality" in ('canonical', 'secondary', 'community'))
);
--> statement-breakpoint
ALTER TABLE "sources" ADD CONSTRAINT "sources_entry_id_entries_id_fk" FOREIGN KEY ("entry_id") REFERENCES "public"."entries"("id") ON DELETE cascade ON UPDATE no action;