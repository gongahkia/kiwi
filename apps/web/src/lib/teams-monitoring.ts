export type TeamsMetricName =
  | "teams_install_total"
  | "teams_metrics_request_total"
  | "teams_search_total";

const counters = new Map<string, { labels: Record<string, string>; value: number }>();

export function incrementTeamsMetric(
  name: TeamsMetricName,
  labels: Record<string, string | number | boolean> = {}
): void {
  const normalized = Object.fromEntries(
    Object.entries(labels).map(([key, value]) => [safeLabelName(key), String(value).slice(0, 80)])
  );
  const key = `${name}${labelSuffix(normalized)}`;
  const current = counters.get(key);
  counters.set(key, { labels: normalized, value: (current?.value ?? 0) + 1 });
}

export function teamsPrometheusMetrics(): string {
  const lines: string[] = [];
  for (const [key, counter] of [...counters.entries()].sort(([left], [right]) =>
    left.localeCompare(right)
  )) {
    const [name] = key.split("{");
    lines.push(`${name}${labelSuffix(counter.labels)} ${counter.value}`);
  }
  return `${lines.join("\n")}\n`;
}

export function resetTeamsMetricsForTest(): void {
  counters.clear();
}

function labelSuffix(labels: Record<string, string>): string {
  const entries = Object.entries(labels).sort(([left], [right]) => left.localeCompare(right));
  if (entries.length === 0) return "";
  return `{${entries.map(([key, value]) => `${key}="${escapeLabelValue(value)}"`).join(",")}}`;
}

function safeLabelName(value: string): string {
  return value.replace(/[^a-zA-Z0-9_]/g, "_");
}

function escapeLabelValue(value: string): string {
  return value.replaceAll("\\", "\\\\").replaceAll("\n", "\\n").replaceAll('"', '\\"');
}
