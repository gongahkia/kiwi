import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { requiredAlerts, requiredSignals, validateAlertRules } from "./validate-alert-rules.mjs";

describe("prometheus alert rules", () => {
  it("cover required wat availability and data-path alerts", () => {
    const result = validateAlertRules(
      readFileSync("infra/monitoring/prometheus-alerts.yml", "utf8")
    );

    assert.equal(result.ok, true);
    assert.deepEqual(result.missingAlerts, []);
    assert.deepEqual(result.missingSignals, []);
  });

  it("fails closed when a required alert is missing", () => {
    const result = validateAlertRules("alert: WatReadyzDown\nexpr: probe_success == 0\n");

    assert.equal(result.ok, false);
    assert.equal(result.missingAlerts.length, requiredAlerts.length - 1);
    assert.equal(result.missingSignals.length, requiredSignals.length - 1);
  });
});
