import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { validateLaunchMetrics } from "./validate-launch-metrics.mjs";

function validMetricsCsv(days = 14) {
  const rows = [
    "date,github_stars,hosted_searches,extension_installs,slack_installs,mcp_installs,docs_visits"
  ];
  for (let day = 1; day <= days; day += 1) {
    const date = `2026-07-${String(day).padStart(2, "0")}`;
    rows.push(`${date},${day},${day * 10},${day + 1},${day + 2},${day + 3},${day * 20}`);
  }
  return rows.join("\n");
}

describe("launch metrics validation", () => {
  it("accepts 14 consecutive daily metric rows", () => {
    assert.deepEqual(validateLaunchMetrics(validMetricsCsv()), {
      errors: [],
      ok: true,
      rows: 14
    });
  });

  it("requires all launch metric columns", () => {
    const result = validateLaunchMetrics("date,github_stars\n2026-07-01,1\n");

    assert.equal(result.ok, false);
    assert.match(result.errors.join("\n"), /missing column: slack_installs/);
    assert.match(result.errors.join("\n"), /expected at least 14 daily rows/);
  });

  it("rejects date gaps and non-integer metrics", () => {
    const csv = validMetricsCsv().replace("2026-07-02,2,20", "2026-07-03,2,nope");
    const result = validateLaunchMetrics(csv);

    assert.equal(result.ok, false);
    assert.match(result.errors.join("\n"), /date is not consecutive/);
    assert.match(result.errors.join("\n"), /hosted_searches must be a non-negative integer/);
  });
});
