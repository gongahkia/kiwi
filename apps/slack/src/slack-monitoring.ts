export type SlackMetricName =
  | "slack_event_total"
  | "slack_http_request_total"
  | "slack_oauth_callback_total"
  | "slack_uninstall_total"
  | "wat_slack_admin_check_total"
  | "wat_slack_command_total"
  | "wat_slack_lookup_total"
  | "wat_slack_write_total";

export interface SlackMonitor {
  increment(name: SlackMetricName, labels?: Record<string, string | number | boolean>): void;
  log(event: string, fields?: Record<string, unknown>): void;
  prometheus(): string;
}

export class InMemorySlackMonitor implements SlackMonitor {
  private readonly counters = new Map<string, { labels: Record<string, string>; value: number }>();

  increment(name: SlackMetricName, labels: Record<string, string | number | boolean> = {}): void {
    const normalizedLabels = normalizeLabels(labels);
    const key = metricKey(name, normalizedLabels);
    const current = this.counters.get(key);
    this.counters.set(key, {
      labels: normalizedLabels,
      value: (current?.value ?? 0) + 1
    });
  }

  log(event: string, fields: Record<string, unknown> = {}): void {
    console.info(JSON.stringify({ event, ...safeLogFields(fields) }));
  }

  prometheus(): string {
    const lines: string[] = [];
    for (const [key, counter] of [...this.counters.entries()].sort(([left], [right]) =>
      left.localeCompare(right)
    )) {
      const [name] = key.split("{");
      lines.push(`${name}${labelSuffix(counter.labels)} ${counter.value}`);
    }
    return `${lines.join("\n")}\n`;
  }
}

let defaultMonitor: SlackMonitor | undefined;

export function defaultSlackMonitor(): SlackMonitor {
  defaultMonitor ??= new InMemorySlackMonitor();
  return defaultMonitor;
}

function normalizeLabels(
  labels: Record<string, string | number | boolean>
): Record<string, string> {
  return Object.fromEntries(
    Object.entries(labels).map(([key, value]) => [safeLabelName(key), String(value).slice(0, 80)])
  );
}

function metricKey(name: SlackMetricName, labels: Record<string, string>): string {
  return `${name}${labelSuffix(labels)}`;
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

function safeLogFields(fields: Record<string, unknown>): Record<string, unknown> {
  const safe: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(fields)) {
    if (/token|secret|authorization|cookie/i.test(key)) continue;
    safe[key] = typeof value === "string" ? value.slice(0, 200) : value;
  }
  return safe;
}
