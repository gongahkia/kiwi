DROP INDEX IF EXISTS "entries_tsvector_gin_idx";--> statement-breakpoint
ALTER TABLE "entries" ADD COLUMN "contemporaries" text[] DEFAULT ARRAY[]::text[] NOT NULL;--> statement-breakpoint
ALTER TABLE "personal_entries" ADD COLUMN "contemporaries" text[] DEFAULT ARRAY[]::text[] NOT NULL;--> statement-breakpoint
ALTER TABLE "team_entries" ADD COLUMN "contemporaries" text[] DEFAULT ARRAY[]::text[] NOT NULL;--> statement-breakpoint
ALTER TABLE "entries" drop column "tsvector";--> statement-breakpoint
ALTER TABLE "entries" ADD COLUMN "tsvector" "tsvector" GENERATED ALWAYS AS (setweight(to_tsvector('english'::regconfig, coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("expansions"), '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("aliases"), '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("related_terms"), '')), 'D') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("contemporaries"), '')), 'D')) STORED;--> statement-breakpoint
ALTER TABLE "personal_entries" drop column "tsvector";--> statement-breakpoint
ALTER TABLE "personal_entries" ADD COLUMN "tsvector" "tsvector" GENERATED ALWAYS AS (setweight(to_tsvector('english'::regconfig, coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("expansions"), '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("aliases"), '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("related_terms"), '')), 'D') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("contemporaries"), '')), 'D')) STORED;--> statement-breakpoint
ALTER TABLE "team_entries" drop column "tsvector";--> statement-breakpoint
ALTER TABLE "team_entries" ADD COLUMN "tsvector" "tsvector" GENERATED ALWAYS AS (setweight(to_tsvector('english'::regconfig, coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("expansions"), '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("aliases"), '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("related_terms"), '')), 'D') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("contemporaries"), '')), 'D')) STORED;--> statement-breakpoint
CREATE INDEX "entries_tsvector_gin_idx" ON "entries" USING gin ("tsvector");--> statement-breakpoint
DROP TRIGGER "entries_embedding_enqueue_trigger" ON "entries";--> statement-breakpoint
CREATE TRIGGER "entries_embedding_enqueue_trigger"
AFTER INSERT OR UPDATE OF "term", "expansions", "meaning_short", "meaning_long", "aliases", "related_terms", "contemporaries"
ON "entries"
FOR EACH ROW
EXECUTE FUNCTION enqueue_entry_embedding_job();
