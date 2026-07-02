CREATE TABLE "search_events" (
	"id" text PRIMARY KEY NOT NULL,
	"team_id" text,
	"actor_id" text,
	"query_hash" text NOT NULL,
	"layer_hits" text[] DEFAULT ARRAY[]::text[] NOT NULL,
	"confidence_distribution" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"result_count" integer DEFAULT 0 NOT NULL,
	"no_result" boolean DEFAULT false NOT NULL,
	"latency_ms" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "search_events" ADD CONSTRAINT "search_events_team_id_teams_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "search_events_team_created_idx" ON "search_events" USING btree ("team_id","created_at");
--> statement-breakpoint
CREATE INDEX "search_events_query_hash_idx" ON "search_events" USING btree ("query_hash");
