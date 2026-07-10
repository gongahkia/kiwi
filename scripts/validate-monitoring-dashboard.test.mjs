import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  requiredDashboardSignals,
  requiredPanelTitles,
  validateMonitoringDashboard
} from "./validate-monitoring-dashboard.mjs";

describe("monitoring dashboard", () => {
  it("covers required production ops panels and signals", () => {
    const result = validateMonitoringDashboard(
      readFileSync("infra/monitoring/grafana-dashboard.json", "utf8")
    );

    assert.equal(result.ok, true);
    assert.deepEqual(result.missingPanelTitles, []);
    assert.deepEqual(result.missingSignals, []);
  });

  it("fails closed when required panels and signals are missing", () => {
    const result = validateMonitoringDashboard(
      JSON.stringify({ panels: [{ title: "Traffic", targets: [] }] })
    );

    assert.equal(result.ok, false);
    assert.deepEqual(result.missingPanelTitles, requiredPanelTitles.slice(1));
    assert.deepEqual(
      result.missingSignals,
      requiredDashboardSignals.map((signal) => signal.label)
    );
  });
});
