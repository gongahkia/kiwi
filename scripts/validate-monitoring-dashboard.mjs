#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const requiredPanelTitles = [
  "Traffic",
  "latency",
  "Search quality",
  "Database",
  "Import",
  "Backups",
  "Slack",
  "Teams",
  "Discord"
];

export const requiredDashboardSignals = [
  { label: "request rate", token: "http_request_duration_seconds_count" },
  { label: "error rate", token: 'status=~"5.."' },
  { label: "web/search latency", token: "http_request_duration_seconds_bucket" },
  { label: "search route latency", token: 'route="/api/v1/search"' },
  { label: "search no-result rate", token: "wat_search_no_result_total" },
  { label: "database connections", token: "pg_stat_database_numbackends" },
  { label: "database CPU", token: "postgres_cpu_percent" },
  { label: "database storage", token: "pg_database_size_bytes" },
  { label: "slow queries", token: "pg_stat_statements_mean_time_seconds" },
  { label: "import failures", token: "wat_import_failed_total" },
  { label: "seed failures", token: "wat_seed_failed_total" },
  { label: "corpus refresh failures", token: "wat_corpus_refresh_failed_total" },
  { label: "scraper failures", token: "wat_scraper_failed_total" },
  { label: "backup age", token: "wat_backup_last_success_timestamp_seconds" },
  { label: "backup verification", token: "wat_backup_verify_success_total" },
  { label: "Slack events", token: "slack_http_request_total" },
  { label: "Slack OAuth", token: "slack_oauth_callback_total" },
  { label: "Slack lookup", token: "wat_slack_lookup_total" },
  { label: "Slack write", token: "wat_slack_write_total" },
  { label: "Slack uninstall", token: "slack_uninstall_total" },
  { label: "Teams search", token: "teams_search_total" },
  { label: "Discord interactions", token: "discord_http_request_total" },
  { label: "Discord lookup", token: "discord_lookup_total" },
  { label: "Discord write", token: "discord_write_total" }
];

function collectPanels(panels = []) {
  return panels.flatMap((panel) => [panel, ...collectPanels(panel.panels ?? [])]);
}

function collectExpressions(panels) {
  return panels
    .flatMap((panel) => panel.targets ?? [])
    .map((target) => target.expr)
    .filter((expr) => typeof expr === "string")
    .join("\n");
}

export function validateMonitoringDashboard(text) {
  let dashboard;
  try {
    dashboard = JSON.parse(text);
  } catch (error) {
    return {
      missingPanelTitles: requiredPanelTitles,
      missingSignals: requiredDashboardSignals.map((signal) => signal.label),
      ok: false,
      parseError: error.message
    };
  }

  const panels = collectPanels(dashboard.panels);
  const panelTitleText = panels.map((panel) => panel.title ?? "").join("\n");
  const expressionText = collectExpressions(panels);
  const missingPanelTitles = requiredPanelTitles.filter(
    (title) => !panelTitleText.toLowerCase().includes(title.toLowerCase())
  );
  const missingSignals = requiredDashboardSignals
    .filter((signal) => !expressionText.includes(signal.token))
    .map((signal) => signal.label);

  return {
    missingPanelTitles,
    missingSignals,
    ok: missingPanelTitles.length === 0 && missingSignals.length === 0
  };
}

function main() {
  const path = process.argv[2] ?? "infra/monitoring/grafana-dashboard.json";
  const result = validateMonitoringDashboard(readFileSync(path, "utf8"));
  if (!result.ok) {
    if (result.parseError) console.error(`dashboard parse error: ${result.parseError}`);
    for (const title of result.missingPanelTitles)
      console.error(`missing dashboard panel: ${title}`);
    for (const signal of result.missingSignals)
      console.error(`missing dashboard signal: ${signal}`);
    process.exit(1);
  }
  console.log(`monitoring dashboard ok: ${path}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
