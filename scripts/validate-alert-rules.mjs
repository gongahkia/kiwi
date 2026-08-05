#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const requiredAlerts = [
  "WatReadyzDown",
  "WatHighSearchLatency",
  "WatDbErrors",
  "WatBackupStale",
  "WatCorpusRefreshFailed",
  "WatSlackEventFailures",
  "WatTeamsSearchFailures",
  "WatDiscordInteractionFailures"
];

export const requiredSignals = [
  "probe_success",
  "/api/v1/search",
  "wat_db_error_total",
  "wat_backup_last_success_timestamp_seconds",
  "wat_corpus_refresh_failed_total",
  "slack_http_request_total",
  "teams_search_total",
  "discord_http_request_total"
];

export function validateAlertRules(text) {
  const missingAlerts = requiredAlerts.filter((alert) => !text.includes(`alert: ${alert}`));
  const missingSignals = requiredSignals.filter((signal) => !text.includes(signal));
  return {
    missingAlerts,
    missingSignals,
    ok: missingAlerts.length === 0 && missingSignals.length === 0
  };
}

function main() {
  const path = process.argv[2] ?? "infra/monitoring/prometheus-alerts.yml";
  const result = validateAlertRules(readFileSync(path, "utf8"));
  if (!result.ok) {
    for (const alert of result.missingAlerts) console.error(`missing alert: ${alert}`);
    for (const signal of result.missingSignals) console.error(`missing signal: ${signal}`);
    process.exit(1);
  }
  console.log(`alert rules ok: ${path}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
