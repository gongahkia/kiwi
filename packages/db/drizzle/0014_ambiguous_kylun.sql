CREATE TABLE "entry_embedding_jobs" (
	"entry_id" text PRIMARY KEY NOT NULL,
	"reason" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"requested_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "entry_embedding_jobs_reason_check" CHECK ("entry_embedding_jobs"."reason" in ('insert', 'update')),
	CONSTRAINT "entry_embedding_jobs_status_check" CHECK ("entry_embedding_jobs"."status" in ('pending', 'processing', 'done', 'failed'))
);
--> statement-breakpoint
ALTER TABLE "entry_embedding_jobs" ADD CONSTRAINT "entry_embedding_jobs_entry_id_entries_id_fk" FOREIGN KEY ("entry_id") REFERENCES "public"."entries"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE OR REPLACE FUNCTION enqueue_entry_embedding_job()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
	INSERT INTO "entry_embedding_jobs" ("entry_id", "reason", "status", "requested_at", "updated_at")
	VALUES (NEW."id", lower(TG_OP), 'pending', now(), now())
	ON CONFLICT ("entry_id") DO UPDATE SET
		"reason" = excluded."reason",
		"status" = 'pending',
		"updated_at" = now();
	RETURN NEW;
END;
$$;
--> statement-breakpoint
CREATE TRIGGER "entries_embedding_enqueue_trigger"
AFTER INSERT OR UPDATE OF "term", "expansions", "meaning_short", "meaning_long", "aliases", "related_terms"
ON "entries"
FOR EACH ROW
EXECUTE FUNCTION enqueue_entry_embedding_job();
