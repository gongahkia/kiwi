CREATE TABLE "personal_entries" (
	"id" text PRIMARY KEY NOT NULL,
	"term" text NOT NULL,
	"term_normalized" text NOT NULL,
	"expansions" text[] DEFAULT ARRAY[]::text[] NOT NULL,
	"domains" text[] DEFAULT ARRAY[]::text[] NOT NULL,
	"meaning_short" text NOT NULL,
	"meaning_long" text NOT NULL,
	"coiner" text,
	"year_coined" integer,
	"confidence_tier" text NOT NULL,
	"license" text NOT NULL,
	"layer" text DEFAULT 'personal' NOT NULL,
	"user_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deprecated" boolean DEFAULT false NOT NULL,
	"deprecated_reason" text,
	"aliases" text[] DEFAULT ARRAY[]::text[] NOT NULL,
	"related_terms" text[] DEFAULT ARRAY[]::text[] NOT NULL,
	"tsvector" "tsvector" GENERATED ALWAYS AS (setweight(to_tsvector('english'::regconfig, coalesce("term", '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("expansions"), '')), 'A') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_short", '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce("meaning_long", '')), 'C') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("aliases"), '')), 'B') ||
          setweight(to_tsvector('english'::regconfig, coalesce(wat_text_array_to_string("related_terms"), '')), 'D')) STORED,
	"embedding" vector(384),
	CONSTRAINT "personal_entries_confidence_tier_check" CHECK ("personal_entries"."confidence_tier" in ('T1', 'T2', 'T3', 'T4')),
	CONSTRAINT "personal_entries_layer_check" CHECK ("personal_entries"."layer" = 'personal')
);
--> statement-breakpoint
ALTER TABLE "personal_entries" ADD CONSTRAINT "personal_entries_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;
