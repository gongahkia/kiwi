export interface SearchBenchmarkReport {
  top_1_hit_rate: number;
  top_5_hit_rate: number;
}

export interface BenchmarkGateResult {
  failures: string[];
  ok: boolean;
}

export function evaluateBenchmarkGate(
  current: SearchBenchmarkReport,
  baseline: SearchBenchmarkReport,
  maxDrop = 0.01
): BenchmarkGateResult {
  const failures = [
    metricFailure("top_1_hit_rate", current.top_1_hit_rate, baseline.top_1_hit_rate, maxDrop),
    metricFailure("top_5_hit_rate", current.top_5_hit_rate, baseline.top_5_hit_rate, maxDrop)
  ].filter((failure): failure is string => failure != null);

  return {
    failures,
    ok: failures.length === 0
  };
}

function metricFailure(
  metric: keyof SearchBenchmarkReport,
  current: number,
  baseline: number,
  maxDrop: number
): string | null {
  const drop = baseline - current;
  if (drop <= maxDrop) return null;
  return `${metric} dropped ${(drop * 100).toFixed(2)}pp`;
}
