#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOOKUP_JSON=$(mktemp)
LIST_JSON=$(mktemp)

cleanup() {
  rm -f "$LOOKUP_JSON" "$LIST_JSON"
}
trap cleanup EXIT

run_mcpjam() {
  MCPJAM_NO_UPDATE_CHECK=1 NO_UPDATE_NOTIFIER=1 npx -y @mcpjam/cli@latest "$@"
}

cd "$ROOT"
pnpm --filter @wat/mcp build

run_mcpjam tools call \
  --command node \
  --args apps/mcp/dist/index.js \
  --cwd "$ROOT" \
  -e WAT_API_KEY=test-key \
  -e WAT_TEAM_ID=team_example \
  -e WAT_TEAM_DOMAINS=example.com \
  --tool-name lookup \
  --tool-args '{"api_key":"test-key","term":"CAP","limit":1}' \
  --quiet \
  --format json >"$LOOKUP_JSON"

run_mcpjam tools call \
  --command node \
  --args apps/mcp/dist/index.js \
  --cwd "$ROOT" \
  -e WAT_API_KEY=test-key \
  -e WAT_TEAM_ID=team_example \
  -e WAT_TEAM_DOMAINS=example.com \
  --tool-name list_team_acronyms \
  --tool-args '{"api_key":"test-key","domain":"example.com","limit":1}' \
  --quiet \
  --format json >"$LIST_JSON"

node --input-type=module - "$LOOKUP_JSON" "$LIST_JSON" <<'NODE'
import { readFileSync } from "node:fs";

const [lookupPath, listPath] = process.argv.slice(2);
const lookup = JSON.parse(readFileSync(lookupPath, "utf8"));
const list = JSON.parse(readFileSync(listPath, "utf8"));

const lookupMatch = lookup.structuredContent?.matches?.[0];
if (lookupMatch?.term !== "CAP" || lookupMatch?.citations?.[0]?.url == null) {
  throw new Error("lookup contract failed");
}

const teamEntry = list.structuredContent?.entries?.[0];
if (teamEntry?.entry_id !== "team-example-cap" || list.structuredContent?.team_id !== "team_example") {
  throw new Error("list_team_acronyms contract failed");
}

console.log("mcp contract ok");
NODE
