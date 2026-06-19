CREATE UNIQUE INDEX "entries_term_layer_team_unique_idx" ON "entries" USING btree ("term_normalized","layer","team_id") NULLS NOT DISTINCT WHERE "entries"."deprecated" = false;
