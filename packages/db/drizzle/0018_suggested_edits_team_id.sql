ALTER TABLE "suggested_edits" ADD COLUMN "team_id" text;
--> statement-breakpoint
ALTER TABLE "suggested_edits" ADD CONSTRAINT "suggested_edits_team_id_teams_id_fk" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "suggested_edits_team_id_status_idx" ON "suggested_edits" USING btree ("team_id","status");
